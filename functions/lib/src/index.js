"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.onUserDeleted = exports.adminDeleteInvitation = exports.adminSetPassword = exports.adminUpdateRole = exports.adminDeleteUser = exports.adminCreateUser = void 0;
const functions = __importStar(require("firebase-functions/v2"));
const admin = __importStar(require("firebase-admin"));
admin.initializeApp();
/**
 * Ensures the caller is authenticated.
 */
function assertAuthenticated(req) {
    if (!req.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'The function must be called while authenticated.');
    }
}
/**
 * Extracts and returns the caller's role, and throws if the user is not an admin
 * nor a pastor of the given targetChurchId (if provided).
 */
async function assertHasPermission(uid, targetChurchId) {
    const profile = await admin.firestore().collection('users').doc(uid).get();
    if (!profile.exists) {
        throw new functions.https.HttpsError('permission-denied', 'El usuario no tiene un perfil en el sistema.');
    }
    const data = profile.data();
    const role = data.role;
    const churchId = data.churchId || null;
    if (role === 'admin') {
        return { role, churchId };
    }
    if (role === 'pastor') {
        if (!targetChurchId) {
            throw new functions.https.HttpsError('permission-denied', 'Los pastores deben especificar la iglesia destino para realizar esta acción.');
        }
        if (churchId !== targetChurchId) {
            throw new functions.https.HttpsError('permission-denied', 'Los pastores solo pueden administrar cuentas de su propia iglesia.');
        }
        return { role, churchId };
    }
    throw new functions.https.HttpsError('permission-denied', 'Solo los administradores y pastores pueden realizar esta acción.');
}
/**
 * Creates or updates a user in Firebase Auth and their profile in Firestore.
 */
exports.adminCreateUser = functions.https.onCall(async (request) => {
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
    const callerUid = request.auth.uid;
    const callerData = await assertHasPermission(callerUid, targetChurchId);
    // Pastors cannot create admins or other pastors
    if (callerData.role === 'pastor') {
        if (targetRole === 'admin' || targetRole === 'pastor') {
            throw new functions.https.HttpsError('permission-denied', 'Un pastor no puede crear administradores ni otros pastores.');
        }
    }
    let userRecord;
    try {
        userRecord = await admin.auth().getUserByEmail(email);
        // User exists. Update password if provided.
        if (password) {
            await admin.auth().updateUser(userRecord.uid, { password });
        }
    }
    catch (error) {
        if (error.code === 'auth/user-not-found') {
            // User doesn't exist. Create.
            if (!password) {
                throw new functions.https.HttpsError('invalid-argument', 'Debe proporcionar una contraseña para la cuenta nueva.');
            }
            userRecord = await admin.auth().createUser({
                email,
                password,
            });
        }
        else {
            throw error;
        }
    }
    // Ensure Firestore profile
    const db = admin.firestore();
    await db.collection('users').doc(userRecord.uid).set({
        email,
        role: targetRole,
        churchId: targetChurchId || null,
        churchName: targetChurchName || null,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    // Delete any pending invitations
    try {
        await db.collection('account_invitations').doc(email).delete();
    }
    catch (e) {
        // ignore
    }
    return { success: true, uid: userRecord.uid };
});
/**
 * Deletes a user from Firebase Auth, Firestore, and any pending invitations.
 */
exports.adminDeleteUser = functions.https.onCall(async (request) => {
    assertAuthenticated(request);
    const { targetUid } = request.data;
    if (!targetUid) {
        throw new functions.https.HttpsError('invalid-argument', 'Falta targetUid.');
    }
    if (targetUid === request.auth.uid) {
        throw new functions.https.HttpsError('permission-denied', 'No puedes eliminarte a ti mismo.');
    }
    const db = admin.firestore();
    const targetProfileRef = db.collection('users').doc(targetUid);
    const targetProfile = await targetProfileRef.get();
    if (!targetProfile.exists) {
        // If it doesn't exist in Firestore, just try to delete from Auth as fallback
        // (requires admin)
        const callerData = await assertHasPermission(request.auth.uid);
        if (callerData.role !== 'admin') {
            throw new functions.https.HttpsError('permission-denied', 'Solo los administradores pueden borrar cuentas sin perfil.');
        }
        await admin.auth().deleteUser(targetUid).catch(() => { });
        return { success: true };
    }
    const targetData = targetProfile.data();
    if (targetData.role === 'admin') {
        // Only an admin can delete another admin
        const callerData = await assertHasPermission(request.auth.uid);
        if (callerData.role !== 'admin') {
            throw new functions.https.HttpsError('permission-denied', 'No tienes permiso para borrar a un administrador.');
        }
    }
    else {
        // Validate permission for the target church
        await assertHasPermission(request.auth.uid, targetData.churchId);
    }
    // 1. Delete from Auth
    try {
        await admin.auth().deleteUser(targetUid);
    }
    catch (e) {
        if (e.code !== 'auth/user-not-found') {
            throw e;
        }
    }
    // 2. Delete from Firestore
    await targetProfileRef.delete();
    // 3. Delete from invitations
    if (targetData.email) {
        await db.collection('account_invitations').doc(targetData.email).delete().catch(() => { });
    }
    return { success: true };
});
/**
 * Updates an existing user's role and church in Firestore.
 */
exports.adminUpdateRole = functions.https.onCall(async (request) => {
    assertAuthenticated(request);
    const { targetUid, role, churchId, churchName } = request.data;
    if (!targetUid || !role) {
        throw new functions.https.HttpsError('invalid-argument', 'Datos incompletos.');
    }
    const db = admin.firestore();
    const targetProfileRef = db.collection('users').doc(targetUid);
    const targetProfile = await targetProfileRef.get();
    if (!targetProfile.exists) {
        throw new functions.https.HttpsError('not-found', 'El usuario no existe.');
    }
    const targetData = targetProfile.data();
    const originalChurchId = targetData.churchId;
    const callerData = await assertHasPermission(request.auth.uid, originalChurchId);
    // Pastors cannot assign admin or pastor roles, nor change a user to another church
    if (callerData.role === 'pastor') {
        if (role === 'admin' || role === 'pastor') {
            throw new functions.https.HttpsError('permission-denied', 'Un pastor no puede asignar el rol de administrador o pastor.');
        }
        if (churchId && churchId !== callerData.churchId) {
            throw new functions.https.HttpsError('permission-denied', 'Los pastores no pueden transferir usuarios a otras iglesias.');
        }
    }
    await targetProfileRef.update({
        role,
        ...(churchId ? { churchId } : {}),
        ...(churchName ? { churchName } : {}),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { success: true };
});
/**
 * Resets a user's password directly via Admin SDK.
 */
exports.adminSetPassword = functions.https.onCall(async (request) => {
    assertAuthenticated(request);
    const { email, newPassword } = request.data;
    if (!email || !newPassword) {
        throw new functions.https.HttpsError('invalid-argument', 'Faltan datos.');
    }
    const db = admin.firestore();
    const existingUsers = await db.collection('users').where('email', '==', email).limit(1).get();
    if (!existingUsers.empty) {
        const targetData = existingUsers.docs[0].data();
        await assertHasPermission(request.auth.uid, targetData.churchId);
    }
    else {
        // If no profile, caller must be admin
        const callerData = await assertHasPermission(request.auth.uid);
        if (callerData.role !== 'admin') {
            throw new functions.https.HttpsError('permission-denied', 'No tienes permiso.');
        }
    }
    let userRecord;
    try {
        userRecord = await admin.auth().getUserByEmail(email);
    }
    catch (error) {
        throw new functions.https.HttpsError('not-found', 'Usuario no encontrado en Authentication.');
    }
    await admin.auth().updateUser(userRecord.uid, { password: newPassword });
    return { success: true };
});
/**
 * Deletes a pending invitation.
 */
exports.adminDeleteInvitation = functions.https.onCall(async (request) => {
    assertAuthenticated(request);
    const { email } = request.data;
    if (!email) {
        throw new functions.https.HttpsError('invalid-argument', 'Falta email.');
    }
    const db = admin.firestore();
    const invRef = db.collection('account_invitations').doc(email);
    const invSnap = await invRef.get();
    if (invSnap.exists) {
        const invData = invSnap.data();
        await assertHasPermission(request.auth.uid, invData.churchId);
        await invRef.delete();
    }
    return { success: true };
});
/**
 * Firestore trigger: When a user document is deleted, ensure the Auth account is also deleted.
 * This acts as a fallback for direct Firestore deletions (e.g., from Firebase Console).
 */
exports.onUserDeleted = functions.firestore
    .onDocumentDeleted('users/{uid}', async (event) => {
    const uid = event.params.uid;
    const data = event.data?.data();
    try {
        await admin.auth().deleteUser(uid);
        console.log(`Successfully deleted Auth account for ${uid}`);
    }
    catch (error) {
        if (error.code !== 'auth/user-not-found') {
            console.error(`Error deleting Auth account for ${uid}:`, error);
        }
    }
    if (data && data.email) {
        try {
            await admin.firestore().collection('account_invitations').doc(data.email).delete();
        }
        catch (e) {
            // ignore
        }
    }
});
//# sourceMappingURL=index.js.map