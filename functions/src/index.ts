import * as functions from 'firebase-functions/v2';
import * as admin from 'firebase-admin';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';

admin.initializeApp();

/**
 * Ensures the caller is authenticated.
 */
function assertAuthenticated(req: functions.https.CallableRequest) {
  if (!req.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'The function must be called while authenticated.'
    );
  }
}

/**
 * Extracts and returns the caller's role, and throws if the user is not an admin
 * nor a pastor of the given targetChurchId (if provided).
 */
async function assertHasPermission(
  uid: string,
  targetChurchId?: string | null
): Promise<{ role: string; churchId: string | null }> {
  const profile = await getFirestore().collection('users').doc(uid).get();
  if (!profile.exists) {
    throw new functions.https.HttpsError(
      'permission-denied',
      'El usuario no tiene un perfil en el sistema.'
    );
  }

  const data = profile.data()!;
  const role = data.role;
  const churchId = data.churchId || null;

  if (role === 'admin') {
    return { role, churchId };
  }

  if (role === 'pastor') {
    if (!targetChurchId) {
      throw new functions.https.HttpsError(
        'permission-denied',
        'Los pastores deben especificar la iglesia destino para realizar esta acción.'
      );
    }
    if (churchId !== targetChurchId) {
      throw new functions.https.HttpsError(
        'permission-denied',
        'Los pastores solo pueden administrar cuentas de su propia iglesia.'
      );
    }
    return { role, churchId };
  }

  throw new functions.https.HttpsError(
    'permission-denied',
    'Solo los administradores y pastores pueden realizar esta acción.'
  );
}

/**
 * Creates or updates a user in Firebase Auth and their profile in Firestore.
 */
export const adminCreateUser = functions.https.onCall(async (request) => {
  assertAuthenticated(request);
  const data = request.data;
  const email = data.email?.trim().toLowerCase();
  const password = data.password;
  const targetRole = data.role;
  const targetChurchId = data.churchId;
  const targetChurchName = data.churchName;

  if (!email || !targetRole) {
    throw new functions.https.HttpsError('invalid-argument', 'Datos incompletos.');
  }

  const callerUid = request.auth!.uid;
  const callerData = await assertHasPermission(callerUid, targetChurchId);

  // Pastors cannot create admins or other pastors
  if (callerData.role === 'pastor') {
    if (targetRole === 'admin' || targetRole === 'pastor') {
      throw new functions.https.HttpsError(
        'permission-denied',
        'Un pastor no puede crear administradores ni otros pastores.'
      );
    }
  }

  let userRecord;
  try {
    userRecord = await getAuth().getUserByEmail(email);
    // User exists. Update password if provided.
    if (password) {
      await getAuth().updateUser(userRecord.uid, { password });
    }
  } catch (error: any) {
    if (error.code === 'auth/user-not-found') {
      // User doesn't exist. Create.
      if (!password) {
        const db = getFirestore();
        await db.collection('account_invitations').doc(email).set({
          email,
          role: targetRole,
          churchId: targetChurchId || null,
          churchName: targetChurchName || null,
          invitedBy: callerUid,
          createdAt: FieldValue.serverTimestamp(),
        });
        return { success: true, invited: true };
      }
      userRecord = await getAuth().createUser({
        email,
        password,
      });
    } else {
      throw error;
    }
  }

  // Ensure Firestore profile
  const db = getFirestore();
  await db.collection('users').doc(userRecord.uid).set({
    email,
    role: targetRole,
    churchId: targetChurchId || null,
    churchName: targetChurchName || null,
    updatedAt: FieldValue.serverTimestamp(),
  });

  // Delete any pending invitations
  try {
    await db.collection('account_invitations').doc(email).delete();
  } catch (e) {
    // ignore
  }

  return { success: true, uid: userRecord.uid };
});

/**
 * Deletes a user from Firebase Auth, Firestore, and any pending invitations.
 */
export const adminDeleteUser = functions.https.onCall(async (request) => {
  assertAuthenticated(request);
  const { targetUid } = request.data;

  if (!targetUid) {
    throw new functions.https.HttpsError('invalid-argument', 'Falta targetUid.');
  }

  if (targetUid === request.auth!.uid) {
    throw new functions.https.HttpsError(
      'permission-denied',
      'No puedes eliminarte a ti mismo.'
    );
  }

  const db = getFirestore();
  const targetProfileRef = db.collection('users').doc(targetUid);
  const targetProfile = await targetProfileRef.get();

  if (!targetProfile.exists) {
    // If it doesn't exist in Firestore, just try to delete from Auth as fallback
    // (requires admin)
    const callerData = await assertHasPermission(request.auth!.uid);
    if (callerData.role !== 'admin') {
      throw new functions.https.HttpsError(
        'permission-denied',
        'Solo los administradores pueden borrar cuentas sin perfil.'
      );
    }
    await getAuth().deleteUser(targetUid).catch(() => {});
    return { success: true };
  }

  const targetData = targetProfile.data()!;
  
  if (targetData.role === 'admin') {
    // Only an admin can delete another admin
    const callerData = await assertHasPermission(request.auth!.uid);
    if (callerData.role !== 'admin') {
      throw new functions.https.HttpsError(
        'permission-denied',
        'No tienes permiso para borrar a un administrador.'
      );
    }

    const adminCountSnap = await db.collection('users').where('role', '==', 'admin').get();
    if (adminCountSnap.size <= 1) {
      throw new functions.https.HttpsError(
        'failed-precondition',
        'No es posible eliminar al único administrador del sistema.'
      );
    }
  } else {
    // Validate permission for the target church
    await assertHasPermission(request.auth!.uid, targetData.churchId);
  }

  // 1. Delete from Auth
  try {
    await getAuth().deleteUser(targetUid);
  } catch (e: any) {
    if (e.code !== 'auth/user-not-found') {
      throw e;
    }
  }

  // 2. Delete from Firestore
  await targetProfileRef.delete();

  // 3. Delete from invitations
  if (targetData.email) {
    await db.collection('account_invitations').doc(targetData.email).delete().catch(() => {});
  }

  return { success: true };
});

/**
 * Updates an existing user's role and church in Firestore.
 */
export const adminUpdateRole = functions.https.onCall(async (request) => {
  assertAuthenticated(request);
  const { targetUid, role, churchId, churchName } = request.data;

  if (!targetUid || !role) {
    throw new functions.https.HttpsError('invalid-argument', 'Datos incompletos.');
  }

  const db = getFirestore();
  const targetProfileRef = db.collection('users').doc(targetUid);
  const targetProfile = await targetProfileRef.get();

  if (!targetProfile.exists) {
    throw new functions.https.HttpsError('not-found', 'El usuario no existe.');
  }

  const targetData = targetProfile.data()!;
  const originalChurchId = targetData.churchId;

  const callerData = await assertHasPermission(request.auth!.uid, originalChurchId);

  // Pastors cannot assign admin or pastor roles, nor change a user to another church
  if (callerData.role === 'pastor') {
    if (role === 'admin' || role === 'pastor') {
      throw new functions.https.HttpsError(
        'permission-denied',
        'Un pastor no puede asignar el rol de administrador o pastor.'
      );
    }
    if (churchId && churchId !== callerData.churchId) {
      throw new functions.https.HttpsError(
        'permission-denied',
        'Los pastores no pueden transferir usuarios a otras iglesias.'
      );
    }
  }

  // Prevent demoting the last administrator
  if (targetData.role === 'admin' && role !== 'admin') {
    const adminCountSnap = await db.collection('users').where('role', '==', 'admin').get();
    if (adminCountSnap.size <= 1) {
      throw new functions.https.HttpsError(
        'failed-precondition',
        'No es posible cambiar el rol del único administrador del sistema.'
      );
    }
  }

  await targetProfileRef.update({
    role,
    ...(churchId ? { churchId } : {}),
    ...(churchName ? { churchName } : {}),
    updatedAt: FieldValue.serverTimestamp(),
  });

  return { success: true };
});

/**
 * Resets a user's password directly via Admin SDK.
 */
export const adminSetPassword = functions.https.onCall(async (request) => {
  assertAuthenticated(request);
  const { email, newPassword } = request.data;

  if (!email || !newPassword) {
    throw new functions.https.HttpsError('invalid-argument', 'Faltan datos.');
  }

  const db = getFirestore();
  const existingUsers = await db.collection('users').where('email', '==', email).limit(1).get();
  
  if (!existingUsers.empty) {
    const targetData = existingUsers.docs[0].data();
    await assertHasPermission(request.auth!.uid, targetData.churchId);
  } else {
    // If no profile, caller must be admin
    const callerData = await assertHasPermission(request.auth!.uid);
    if (callerData.role !== 'admin') {
      throw new functions.https.HttpsError(
        'permission-denied',
        'No tienes permiso.'
      );
    }
  }

  let userRecord;
  try {
    userRecord = await getAuth().getUserByEmail(email);
  } catch (error: any) {
    throw new functions.https.HttpsError('not-found', 'Usuario no encontrado en Authentication.');
  }

  await getAuth().updateUser(userRecord.uid, { password: newPassword });
  return { success: true };
});

/**
 * Deletes a pending invitation.
 */
export const adminDeleteInvitation = functions.https.onCall(async (request) => {
  assertAuthenticated(request);
  const { email } = request.data;

  if (!email) {
    throw new functions.https.HttpsError('invalid-argument', 'Falta email.');
  }

  const db = getFirestore();
  const invRef = db.collection('account_invitations').doc(email);
  const invSnap = await invRef.get();

  if (invSnap.exists) {
    const invData = invSnap.data()!;
    await assertHasPermission(request.auth!.uid, invData.churchId);
    await invRef.delete();
  }

  return { success: true };
});

/**
 * Firestore trigger: When a user document is deleted, ensure the Auth account is also deleted.
 * This acts as a fallback for direct Firestore deletions (e.g., from Firebase Console).
 */
export const onUserDeleted = functions.firestore
  .onDocumentDeleted('users/{uid}', async (event) => {
    const uid = event.params.uid;
    const data = event.data?.data();

    try {
      await getAuth().deleteUser(uid);
      console.log(`Successfully deleted Auth account for ${uid}`);
    } catch (error: any) {
      if (error.code !== 'auth/user-not-found') {
        console.error(`Error deleting Auth account for ${uid}:`, error);
      }
    }

    if (data && data.email) {
      try {
        await getFirestore().collection('account_invitations').doc(data.email).delete();
      } catch (e) {
        // ignore
      }
    }
  });
