import * as fs from 'fs';
import * as path from 'path';
import {
  initializeTestEnvironment,
  RulesTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc, deleteDoc } from 'firebase/firestore';

const PROJECT_ID = 'cgdi-rules-test';

describe('Firestore Security Rules Matrix & Church Isolation Tests', () => {
  let testEnv: RulesTestEnvironment;

  before(async function () {
    this.timeout(25000);
    const rulesPath = path.resolve(__dirname, '../../firestore.rules');
    const rules = fs.readFileSync(rulesPath, 'utf8');

    // Inicializar entorno conectado al emulador de Firestore
    testEnv = await initializeTestEnvironment({
      projectId: PROJECT_ID,
      firestore: {
        rules,
        host: '127.0.0.1',
        port: 8085,
      },
    });
  });

  after(async () => {
    if (testEnv) {
      await testEnv.cleanup();
    }
  });

  beforeEach(async () => {
    await testEnv.clearFirestore();

    // Cargar perfiles de usuarios de prueba en bypass de reglas
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();

      // 1. Admin General
      await setDoc(doc(db, 'users/admin_user'), {
        email: 'admin@cgdi.org',
        role: 'admin',
      });

      // 2. Pastor Iglesia A
      await setDoc(doc(db, 'users/pastor_a'), {
        email: 'pastor.a@cgdi.org',
        role: 'pastor',
        churchId: 'church_a',
        churchName: 'Iglesia A',
      });

      // 3. Pastor Iglesia B
      await setDoc(doc(db, 'users/pastor_b'), {
        email: 'pastor.b@cgdi.org',
        role: 'pastor',
        churchId: 'church_b',
        churchName: 'Iglesia B',
      });

      // 4. Colaborador Iglesia A
      await setDoc(doc(db, 'users/colaborador_a'), {
        email: 'colaborador.a@cgdi.org',
        role: 'colaborador',
        churchId: 'church_a',
        churchName: 'Iglesia A',
      });

      // 5. Proyeccionista Iglesia A
      await setDoc(doc(db, 'users/proyeccionista_a'), {
        email: 'proyeccionista.a@cgdi.org',
        role: 'proyeccionista',
        churchId: 'church_a',
        churchName: 'Iglesia A',
      });

      // 6. Iglesia A y B documentos base
      await setDoc(doc(db, 'churches/church_a'), {
        name: 'Iglesia A',
        region: 'norte',
        weeklyServices: ['Sabado 10:00'],
        defaultMeetUrl: 'https://meet.google.com/aaa-bbbb-ccc',
        audioStreamUrl: 'https://radio.cgdi.org/stream_a',
      });
      await setDoc(doc(db, 'churches/church_b'), {
        name: 'Iglesia B',
        region: 'sur',
        weeklyServices: ['Sabado 11:00'],
        defaultMeetUrl: 'https://meet.google.com/bbb-cccc-ddd',
        audioStreamUrl: 'https://radio.cgdi.org/stream_b',
      });
    });
  });

  describe('1. Reglas de Iglesias (Aislamiento y Modificación Operativa)', () => {
    it('Cualquier persona puede leer la información de una iglesia', async () => {
      const unauthDb = testEnv.unauthenticatedContext().firestore();
      await assertSucceeds(getDoc(doc(unauthDb, 'churches/church_a')));
    });

    it('Admin General puede crear y modificar cualquier campo de una iglesia', async () => {
      const adminDb = testEnv.authenticatedContext('admin_user').firestore();
      await assertSucceeds(
        setDoc(doc(adminDb, 'churches/church_new'), {
          name: 'Iglesia Nueva',
          region: 'centro',
        })
      );
    });

    it('Pastor puede modificar campos operativos de su iglesia asignada', async () => {
      const pastorADb = testEnv.authenticatedContext('pastor_a').firestore();
      await assertSucceeds(
        updateDoc(doc(pastorADb, 'churches/church_a'), {
          weeklyServices: ['Sabado 09:30', 'Miercoles 19:00'],
          audioStreamUrl: 'https://radio.cgdi.org/stream_a_nueva',
        })
      );
    });

    it('Pastor NO puede alterar nombre, región o campos estructurales de su iglesia', async () => {
      const pastorADb = testEnv.authenticatedContext('pastor_a').firestore();
      await assertFails(
        updateDoc(doc(pastorADb, 'churches/church_a'), {
          name: 'Nombre Cambiado Ilegalmente',
        })
      );
    });

    it('Pastor NO puede modificar otra iglesia ajena', async () => {
      const pastorADb = testEnv.authenticatedContext('pastor_a').firestore();
      await assertFails(
        updateDoc(doc(pastorADb, 'churches/church_b'), {
          weeklyServices: ['Sabado 12:00'],
        })
      );
    });

    it('Colaborador o Proyeccionista NO pueden modificar la iglesia', async () => {
      const colabADb = testEnv.authenticatedContext('colaborador_a').firestore();
      await assertFails(
        updateDoc(doc(colabADb, 'churches/church_a'), {
          audioStreamUrl: 'https://hack.org',
        })
      );
    });
  });

  describe('2. Avisos Semanales (Notices Subcollection)', () => {
    it('Cualquiera puede leer avisos de una iglesia', async () => {
      const unauthDb = testEnv.unauthenticatedContext().firestore();
      await assertSucceeds(getDoc(doc(unauthDb, 'churches/church_a/notices/aviso_1')));
    });

    it('Pastor y Colaborador asignados pueden crear avisos para su iglesia', async () => {
      const pastorADb = testEnv.authenticatedContext('pastor_a').firestore();
      await assertSucceeds(
        setDoc(doc(pastorADb, 'churches/church_a/notices/aviso_pastor'), {
          title: 'Santa Cena el próximo sábado',
          body: 'Favor de estar puntuales',
        })
      );

      const colabADb = testEnv.authenticatedContext('colaborador_a').firestore();
      await assertSucceeds(
        setDoc(doc(colabADb, 'churches/church_a/notices/aviso_colaborador'), {
          title: 'Reunión de directiva',
        })
      );
    });

    it('Pastor o Colaborador NO pueden crear avisos en otra iglesia ajena', async () => {
      const pastorADb = testEnv.authenticatedContext('pastor_a').firestore();
      await assertFails(
        setDoc(doc(pastorADb, 'churches/church_b/notices/aviso_ilegal'), {
          title: 'Aviso infiltrado',
        })
      );
    });
  });

  describe('3. Eventos y Convocatorias (Events)', () => {
    it('Admin General puede crear eventos nacionales, regionales y locales', async () => {
      const adminDb = testEnv.authenticatedContext('admin_user').firestore();
      await assertSucceeds(
        setDoc(doc(adminDb, 'events/convocatoria_nacional'), {
          title: 'Conferencia Nacional 2026',
          scope: 'nacional',
        })
      );
    });

    it('Pastor y Colaborador pueden crear eventos locales únicamente para su iglesia', async () => {
      const pastorADb = testEnv.authenticatedContext('pastor_a').firestore();
      await assertSucceeds(
        setDoc(doc(pastorADb, 'events/evento_local_a'), {
          title: 'Vigilia de Alabanza',
          scope: 'local',
          churchId: 'church_a',
        })
      );
    });

    it('Pastor NO puede crear eventos de alcance nacional o regional', async () => {
      const pastorADb = testEnv.authenticatedContext('pastor_a').firestore();
      await assertFails(
        setDoc(doc(pastorADb, 'events/evento_regional_ilegal'), {
          title: 'Campamento Regional No Autorizado',
          scope: 'regional',
          churchId: 'church_a',
        })
      );
    });

    it('Pastor NO puede crear eventos locales para otra iglesia', async () => {
      const pastorADb = testEnv.authenticatedContext('pastor_a').firestore();
      await assertFails(
        setDoc(doc(pastorADb, 'events/evento_ajeno'), {
          title: 'Evento en Iglesia Ajena',
          scope: 'local',
          churchId: 'church_b',
        })
      );
    });

    it('Colaborador NO puede eliminar eventos (solo Pastor y Admin pueden)', async () => {
      // Crear evento local previo
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await setDoc(doc(context.firestore(), 'events/evento_a_borrar'), {
          title: 'Evento Local',
          scope: 'local',
          churchId: 'church_a',
        });
      });

      const colabADb = testEnv.authenticatedContext('colaborador_a').firestore();
      await assertFails(deleteDoc(doc(colabADb, 'events/evento_a_borrar')));

      const pastorADb = testEnv.authenticatedContext('pastor_a').firestore();
      await assertSucceeds(deleteDoc(doc(pastorADb, 'events/evento_a_borrar')));
    });
  });

  describe('4. Gestión de Equipos y Usuarios (Users & Invitations)', () => {
    it('Pastor puede crear colaborador, proyeccionista o músico en su propia iglesia', async () => {
      const pastorADb = testEnv.authenticatedContext('pastor_a').firestore();
      await assertSucceeds(
        setDoc(doc(pastorADb, 'users/nuevo_musico'), {
          email: 'musico.nuevo@cgdi.org',
          role: 'musico',
          churchId: 'church_a',
          churchName: 'Iglesia A',
        })
      );
    });

    it('Pastor NO puede crear otro pastor ni administrador', async () => {
      const pastorADb = testEnv.authenticatedContext('pastor_a').firestore();
      await assertFails(
        setDoc(doc(pastorADb, 'users/nuevo_pastor'), {
          email: 'pastor.falso@cgdi.org',
          role: 'pastor',
          churchId: 'church_a',
          churchName: 'Iglesia A',
        })
      );

      await assertFails(
        setDoc(doc(pastorADb, 'users/nuevo_admin'), {
          email: 'admin.falso@cgdi.org',
          role: 'admin',
        })
      );
    });

    it('Pastor NO puede registrar usuarios asignados a otra iglesia', async () => {
      const pastorADb = testEnv.authenticatedContext('pastor_a').firestore();
      await assertFails(
        setDoc(doc(pastorADb, 'users/usuario_iglesia_b'), {
          email: 'colab.b@cgdi.org',
          role: 'colaborador',
          churchId: 'church_b',
          churchName: 'Iglesia B',
        })
      );
    });

    it('Usuario normal no puede elevarse a admin', async () => {
      const colabADb = testEnv.authenticatedContext('colaborador_a').firestore();
      await assertFails(
        updateDoc(doc(colabADb, 'users/colaborador_a'), {
          role: 'admin',
        })
      );
    });
  });
});
