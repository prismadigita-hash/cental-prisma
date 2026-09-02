/* Central Prisma — Service Worker */
const CACHE = 'cp-v2';
const ASSETS = [
  './manifest.json', './icon-192.png', './icon-512.png', './apple-touch-icon.png',
  'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2'
];
self.addEventListener('install', e=>{
  e.waitUntil(caches.open(CACHE).then(c=>c.addAll(ASSETS).catch(()=>{})).then(()=>self.skipWaiting()));
});
self.addEventListener('activate', e=>{
  e.waitUntil(caches.keys().then(ks=>Promise.all(ks.filter(k=>k!==CACHE).map(k=>caches.delete(k)))).then(()=>self.clients.claim()));
});
self.addEventListener('fetch', e=>{
  const req = e.request;
  if(req.method !== 'GET') return;
  const url = new URL(req.url);
  // dados dinâmicos e vídeo: sempre pela rede
  if(url.hostname.includes('supabase.co') || url.hostname.includes('youtube') || url.hostname.includes('ytimg') || url.hostname.includes('googlevideo')) return;
  // o app (HTML): NETWORK-FIRST — sempre pega a versão nova; cache só serve offline
  const isDoc = req.mode==='navigate' || (url.origin===location.origin && (url.pathname==='/' || url.pathname.endsWith('/') || url.pathname.endsWith('.html')));
  if(isDoc){
    e.respondWith(
      fetch(req).then(res=>{ const copy=res.clone(); caches.open(CACHE).then(c=>c.put(req,copy)); return res; })
                .catch(()=> caches.match(req).then(r=> r || caches.match('./index.html')))
    );
    return;
  }
  // estáticos (ícones, fontes, supabase-js versionado): CACHE-FIRST
  e.respondWith(
    caches.match(req).then(cached => cached || fetch(req).then(res=>{
      if(res && res.ok && (url.origin===location.origin || url.hostname.includes('jsdelivr') || url.hostname.includes('gstatic'))){
        const copy=res.clone(); caches.open(CACHE).then(c=>c.put(req, copy));
      }
      return res;
    }).catch(()=>undefined))
  );
});
