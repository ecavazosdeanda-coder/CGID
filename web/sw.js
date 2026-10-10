const CACHE_NAME = 'cgdi-v2-cache-2.0.0-rc.1-downloads';

// Recursos estáticos iniciales a cachear para asegurar funcionamiento offline
const PRECACHE_ASSETS = [
  './',
  'index.html',
  'manifest.json',
  'favicon.png',
  'favicon-gold.png',
  'icons/Icon-192.png',
  'icons/Icon-512.png',
  'score_viewer.html',
  'vendor/opensheetmusicdisplay.min.js'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      return cache.addAll(PRECACHE_ASSETS).catch((err) => {
        console.warn('[CGDI SW] Precache warning:', err);
      });
    }).then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((cacheNames) => {
      return Promise.all(
        cacheNames.map((name) => {
          if (name !== CACHE_NAME) {
            return caches.delete(name);
          }
        })
      );
    }).then(() => self.clients.claim())
  );
});

// Estrategia Network-First con fallback a Cache para datos y Cache-First para assets locales
self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);

  // Ignorar llamadas de esquemas no HTTP/HTTPS o extensiones
  if (!event.request.url.startsWith('http')) return;

  // Para Firebase Auth o Firestore APIs, dejar pasar directo a la red sin interceptar
  if (url.hostname.includes('firebase') || url.hostname.includes('googleapis.com') || url.hostname.includes('identitytoolkit')) {
    return;
  }

  // Assets estáticos de la aplicación (assets, fonts, js, icons): Cache-First
  if (url.pathname.includes('/assets/') || url.pathname.endsWith('.js') || url.pathname.endsWith('.png') || url.pathname.endsWith('.json') || url.pathname.endsWith('.mxl')) {
    event.respondWith(
      caches.match(event.request).then((cachedResponse) => {
        if (cachedResponse) {
          // Revalidar en segundo plano
          fetch(event.request).then((networkResponse) => {
            if (networkResponse && networkResponse.status === 200) {
              caches.open(CACHE_NAME).then((cache) => cache.put(event.request, networkResponse));
            }
          }).catch(() => {});
          return cachedResponse;
        }

        return fetch(event.request).then((networkResponse) => {
          if (networkResponse && networkResponse.status === 200) {
            const responseClone = networkResponse.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put(event.request, responseClone));
          }
          return networkResponse;
        });
      })
    );
    return;
  }

  // Documentos HTML / Navegación: Network-First con fallback a Caché
  event.respondWith(
    fetch(event.request).then((networkResponse) => {
      if (networkResponse && networkResponse.status === 200) {
        const responseClone = networkResponse.clone();
        caches.open(CACHE_NAME).then((cache) => cache.put(event.request, responseClone));
      }
      return networkResponse;
    }).catch(() => {
      return caches.match(event.request).then((cached) => {
        return cached || caches.match('index.html');
      });
    })
  );
});

// Soporte para Notificaciones Web Push y Recordatorios Litúrgicos de Cultos
self.addEventListener('push', (event) => {
  let title = 'Conferencia General de la Iglesia de Dios';
  let options = {
    body: 'El culto comenzará en breve. Haz clic para unirte a la transmisión.',
    icon: 'icons/Icon-192.png',
    badge: 'favicon-gold.png',
    tag: 'cgdi-service-reminder',
    renotify: true,
    data: { url: './#/home' },
  };

  if (event.data) {
    try {
      const data = event.data.json();
      if (data.title) title = data.title;
      if (data.body) options.body = data.body;
      if (data.icon) options.icon = data.icon;
      if (data.data) options.data = data.data;
    } catch (_) {
      options.body = event.data.text();
    }
  }

  event.waitUntil(self.registration.showNotification(title, options));
});

// Al pulsar la notificación, enfocar o abrir la ventana del culto
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const targetUrl = event.notification.data && event.notification.data.url
    ? event.notification.data.url
    : './#/home';

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
      for (const client of clientList) {
        if ('focus' in client) {
          if (targetUrl.startsWith('http') && !targetUrl.includes(location.origin)) {
            // URL externa como Google Meet
            if ('openWindow' in clients) return clients.openWindow(targetUrl);
          }
          return client.focus();
        }
      }
      if (clients.openWindow) {
        return clients.openWindow(targetUrl);
      }
    })
  );
});

