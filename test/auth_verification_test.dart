import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cgid/features/admin/providers/auth_provider.dart';
import 'package:cgid/features/admin/providers/user_profile_provider.dart';

class TestUser implements User {
  TestUser({this.verified = false, this.sendError});
  bool verified;
  Object? sendError;
  int emailsSent = 0;
  int deletions = 0;
  @override
  String get uid => 'new-user';
  @override
  String get email => 'pastor@example.com';
  @override
  bool get emailVerified => verified;
  @override
  Future<void> sendEmailVerification([ActionCodeSettings? settings]) async {
    emailsSent++;
    if (sendError != null) throw sendError!;
  }

  @override
  Future<void> delete() async => deletions++;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestCredential implements UserCredential {
  TestCredential(this.user);
  @override
  final User user;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestAuth implements FirebaseAuth {
  TestAuth(this.user);
  final TestUser user;
  int signOuts = 0;
  String? lastEmail;
  Object? signInError;
  @override
  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    lastEmail = email;
    return TestCredential(user);
  }

  @override
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    lastEmail = email;
    if (signInError != null) throw signInError!;
    return TestCredential(user);
  }

  @override
  Future<void> signOut() async => signOuts++;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ExistingProfileStore implements FirebaseFirestore {
  int reads = 0;
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) {
    reads++;
    return TestCollection();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Dobles de prueba: no implementaciones de Firestore para producción.
// ignore: subtype_of_sealed_class
class TestCollection implements CollectionReference<Map<String, dynamic>> {
  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) => TestDocument();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class TestDocument implements DocumentReference<Map<String, dynamic>> {
  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async => TestSnapshot();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class TestSnapshot implements DocumentSnapshot<Map<String, dynamic>> {
  @override
  bool get exists => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Matcher authError(String code) =>
    isA<FirebaseAuthException>().having((e) => e.code, 'code', code);

void main() {
  test(
    'perfil no consume invitación ni consulta Firestore antes de verificar',
    () async {
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith((ref) => Stream.value(TestUser())),
        ],
      );
      addTearDown(container.dispose);
      container.listen(authStateProvider, (_, _) {});
      await container.read(authStateProvider.future);
      container.listen(userProfileProvider, (_, _) {});
      // Firebase no se inicializa en esta prueba: acceder a Firestore fallaría.
      expect(await container.read(userProfileProvider.future), isNull);
    },
  );

  test('alta envía verificación, normaliza correo y cierra sesión', () async {
    final user = TestUser();
    final auth = TestAuth(user);
    await AuthService(auth: auth).activateAccountWithEmail(
      email: ' Pastor@Example.com ',
      password: 'secret123',
    );
    expect(auth.lastEmail, 'pastor@example.com');
    expect(user.emailsSent, 1);
    expect(auth.signOuts, 1);
  });

  test('fallo de envío conserva cuenta y permite reenviar', () async {
    final user = TestUser(
      sendError: FirebaseAuthException(code: 'network-request-failed'),
    );
    final auth = TestAuth(user);
    final service = AuthService(auth: auth);
    await expectLater(
      service.activateAccountWithEmail(
        email: user.email,
        password: 'secret123',
      ),
      throwsA(authError('verification-email-failed')),
    );
    expect(user.deletions, 0);
    expect(auth.signOuts, 1);
    user.sendError = null;
    await service.resendVerificationEmail(user.email, 'secret123');
    expect(user.emailsSent, 2);
    expect(auth.signOuts, 2);
  });

  test('perfil existente no permite saltarse la verificación ni manda correos al ingresar', () async {
    final user = TestUser();
    final auth = TestAuth(user);
    final db = ExistingProfileStore();
    await expectLater(
      AuthService(
        auth: auth,
        firestore: db,
      ).signInWithEmail(user.email, 'secret123'),
      throwsA(authError('email-not-verified')),
    );
    expect(db.reads, 0);
    expect(user.emailsSent, 0);
    expect(auth.signOuts, 1);
  });

  test(
    'cuenta verificada con perfil puede ingresar sin reenviar correo',
    () async {
      final user = TestUser(verified: true);
      final auth = TestAuth(user);
      await AuthService(
        auth: auth,
        firestore: ExistingProfileStore(),
      ).signInWithEmail(user.email, 'secret123');
      expect(user.emailsSent, 0);
      expect(auth.signOuts, 0);
    },
  );

  test(
    'reenvío no envía correo para cuentas ya verificadas y cierra sesión',
    () async {
      final user = TestUser(verified: true);
      final auth = TestAuth(user);
      await expectLater(
        AuthService(auth: auth)
            .resendVerificationEmail(user.email, 'secret123'),
        throwsA(authError('email-already-verified')),
      );
      expect(user.emailsSent, 0);
      expect(auth.signOuts, 1);
    },
  );

  test('reenvío exige contraseña correcta y no accede a Firestore', () async {
    final user = TestUser();
    final auth = TestAuth(user)
      ..signInError = FirebaseAuthException(code: 'invalid-credential');
    final db = ExistingProfileStore();
    await expectLater(
      AuthService(
        auth: auth,
        firestore: db,
      ).resendVerificationEmail(user.email, 'wrong'),
      throwsA(authError('invalid-credential')),
    );
    expect(user.emailsSent, 0);
    expect(db.reads, 0);
    expect(auth.signOuts, 1);
  });

  test(
    'límite de Firebase se informa como fallo de envío, no como envío exitoso',
    () async {
      final user = TestUser(
        sendError: FirebaseAuthException(code: 'too-many-requests'),
      );
      await expectLater(
        sendVerificationEmail(user),
        throwsA(
          isA<FirebaseAuthException>()
              .having((e) => e.code, 'code', 'verification-email-failed')
              .having(
                (e) => e.message,
                'message',
                contains('Espera unos minutos'),
              ),
        ),
      );
    },
  );
}
