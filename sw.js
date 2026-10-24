const V="rasad-v4";
const SHELL=["./","index.html","config.js","manifest.webmanifest","icon-192.png","icon-512.png","privacy.html"];
self.addEventListener("install",e=>{e.waitUntil(caches.open(V).then(c=>Promise.all(SHELL.map(u=>c.add(u).catch(()=>{})))).then(()=>self.skipWaiting()))});
self.addEventListener("activate",e=>{e.waitUntil(caches.keys().then(ks=>Promise.all(ks.filter(k=>k!==V).map(k=>caches.delete(k)))).then(()=>self.clients.claim()))});
self.addEventListener("fetch",e=>{
 const r=e.request;if(r.method!=="GET")return;
 const u=new URL(r.url);
 if(u.hostname.endsWith("supabase.co"))return;           // لا نخزّن بيانات القاعدة أبداً
 if(u.origin!==location.origin&&u.hostname!=="cdn.jsdelivr.net")return;
 e.respondWith(fetch(r).then(res=>{if(res&&(res.ok||res.type==="opaque")){const c=res.clone();caches.open(V).then(ch=>ch.put(r,c))}return res}).catch(()=>caches.match(r).then(x=>x||(r.mode==="navigate"?caches.match("index.html"):Response.error()))));
});
