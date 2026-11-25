/* Project X distribution portal — local demo.
   The key format matches Discord.app's LicenseGate.swift exactly:
   X-YYYYMMDD-PAYLOAD-CHECK where CHECK = SHA256("zada-license-v1|DATE|PAYLOAD")[0..4]. */

const SALT = 'zada-license-v1';
const STORE = {
  key: 'px_key',
  device: 'px_device',
  revoked: 'px_revoked',
  profile: 'px_profile',
  lastKey: 'px_last_key',
  downloads: 'px_downloads',
  visits: 'px_visits'
};

const SIG_LINKS = {
  esign: [
    ['ESign · Beihang', 'itms-services://?action=download-manifest&url=https://raw.githubusercontent.com/davidum19/Delt4-OTA/refs/heads/main/beihang/manifest.plist'],
    ['ESign · National', 'itms-services://?action=download-manifest&url=https://raw.githubusercontent.com/davidum19/Delt4-OTA/refs/heads/main/nuevonational/manifest.plist'],
    ['ESign · HSBC', 'itms-services://?action=download-manifest&url=https://raw.githubusercontent.com/davidum19/Delt4-OTA/refs/heads/main/hsbc/esign.plist'],
    ['ESign · CenPower', 'itms-services://?action=download-manifest&url=https://raw.githubusercontent.com/davidum19/Delt4-OTA/refs/heads/main/cenpower/manifest.plist'],
    ['ESign · Comision', 'itms-services://?action=download-manifest&url=https://raw.githubusercontent.com/davidum19/Delt4-OTA/refs/heads/main/comision/manifest.plist']
  ],
  ksign: [
    ['KSign · Beihang', 'itms-services://?action=download-manifest&url=https://raw.githubusercontent.com/davidum19/Delt4-OTA/refs/heads/main/beihang/manifest.plist'],
    ['KSign · China Limited', 'itms-services://?action=download-manifest&url=https://raw.githubusercontent.com/davidum19/Delt4-OTA/refs/heads/main/cert1/manifest.plist'],
    ['KSign · HSBC', 'itms-services://?action=download-manifest&url=https://raw.githubusercontent.com/davidum19/Delt4-OTA/refs/heads/main/hsbcksign/ksignsigned.plist'],
    ['KSign · VietNam Rubber', 'https://api.khoindvn.io.vn/JnAsbd'],
    ['KSign · PowerChina', 'https://api.khoindvn.io.vn/03zH0o']
  ],
  scarlet: [
    ['Scarlet · Beihang', 'itms-services://?action=download-manifest&url=https://raw.githubusercontent.com/davidum19/Delt4-OTA/refs/heads/main/scarbb/manifest.plist'],
    ['Scarlet · CenPower', 'itms-services://?action=download-manifest&url=https://raw.githubusercontent.com/davidum19/Delt4-OTA/refs/heads/main/commi/manifest.plist'],
    ['Scarlet · Airlines', 'https://davidum19.github.io/Delt4-OTA/airlines/index.html'],
    ['Scarlet · Aramco', 'https://loadly.io/933ff81f7ffe05e3063b5884a235912b']
  ],
  gbox: [
    ['GBox+ · Aramco', 'https://loadly.io/801d312fdf38684573611e624aaa48dc'],
    ['GBox+ · BUPT', 'https://loadly.io/ad6db71f15b55249b71f6f0a90307cff'],
    ['GBox+ · CHINA TELECOM', 'https://i.loadly.io/f2753ab8f9f87cde004ee282e70ed7ca']
  ]
};

const $ = id => document.getElementById(id);

function inc(name) {
  const n = Number(localStorage.getItem(STORE[name]) || 0) + 1;
  localStorage.setItem(STORE[name], String(n));
  return n;
}

function trackDownload() {
  const n = inc('downloads');
  $('stat-downloads').textContent = n;
  $('m-downloads').textContent = n;
}

function switchTab(tab) {
  document.querySelectorAll('.tab').forEach(el => el.classList.toggle('active', el.id === 'tab-' + tab));
  document.querySelectorAll('.nav-link').forEach(el => el.classList.toggle('active', el.dataset.tab === tab));
  if (tab === 'profile') renderProfile();
  window.scrollTo({ top: 0, behavior: 'smooth' });
}

function copyText(value, button) {
  navigator.clipboard.writeText(value).then(() => {
    if (!button) return;
    const old = button.textContent;
    button.textContent = 'Copiado';
    setTimeout(() => { button.textContent = old; }, 1200);
  });
}

// ---- key system -----------------------------------------------------------

async function sha256Hex(text) {
  const bytes = new TextEncoder().encode(text);
  const hash = await crypto.subtle.digest('SHA-256', bytes);
  return Array.from(new Uint8Array(hash)).map(b => b.toString(16).padStart(2, '0')).join('');
}

async function expectedChecksum(date, payload) {
  return (await sha256Hex(`${SALT}|${date}|${payload}`)).slice(0, 4).toUpperCase();
}

function yyyymmdd(date) {
  const y = date.getUTCFullYear();
  const m = String(date.getUTCMonth() + 1).padStart(2, '0');
  const d = String(date.getUTCDate()).padStart(2, '0');
  return `${y}${m}${d}`;
}

function parseDate(text) {
  const y = Number(text.slice(0, 4));
  const m = Number(text.slice(4, 6)) - 1;
  const d = Number(text.slice(6, 8));
  const date = new Date(Date.UTC(y, m, d));
  return isNaN(date.getTime()) ? null : date;
}

function randomPayload() {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  let out = '';
  const bytes = new Uint8Array(8);
  crypto.getRandomValues(bytes);
  for (const b of bytes) out += alphabet[b % alphabet.length];
  return out;
}

function deviceID() {
  let id = localStorage.getItem(STORE.device);
  if (!id) {
    id = Array.from(crypto.getRandomValues(new Uint8Array(16)))
      .map(b => b.toString(16).padStart(2, '0')).join('').toUpperCase().slice(0, 16);
    localStorage.setItem(STORE.device, id);
  }
  return id;
}

async function generateKey(days) {
  const expiry = new Date(Date.now() + days * 86400000);
  const date = yyyymmdd(expiry);
  const payload = randomPayload();
  const check = await expectedChecksum(date, payload);
  return `X-${date}-${payload}-${check}`;
}

async function checkKey(raw) {
  const key = String(raw || '').trim().toUpperCase();
  const revoked = JSON.parse(localStorage.getItem(STORE.revoked) || '[]');

  if (!key) return { active: false, reason: 'key_missing' };
  if (revoked.includes(key)) return { active: false, reason: 'revoked' };

  if (key.startsWith('X-')) {
    const m = key.match(/^X-([0-9]{8})-([A-Z0-9]{8})-([A-F0-9]{4})$/);
    if (!m) return { active: false, reason: 'rejected' };
    if (await expectedChecksum(m[1], m[2]) !== m[3]) return { active: false, reason: 'rejected' };
    const expiry = parseDate(m[1]);
    if (!expiry) return { active: false, reason: 'unreadable_response' };
    if (expiry <= new Date()) return { active: false, reason: 'expired', expiry };
    const linked = localStorage.getItem(STORE.key + '_device');
    if (linked && linked !== deviceID()) return { active: false, reason: 'revoked', expiry };
    return { active: true, reason: null, status: 'granted', expiry, legacy: false };
  }

  if (!/^[A-Z0-9][A-Z0-9-]{7,63}$/.test(key)) return { active: false, reason: 'rejected' };
  const linked = localStorage.getItem(STORE.key + '_device');
  if (linked && linked !== deviceID()) return { active: false, reason: 'revoked' };
  const start = Number(localStorage.getItem(STORE.key + '_at') || Date.now());
  const expiry = new Date(start + 365 * 86400000);
  return { active: true, reason: null, status: 'granted', expiry, legacy: true };
}

async function generateFreeKey() {
  const last = Number(localStorage.getItem(STORE.lastKey) || 0);
  const note = $('fk-note');
  if (Date.now() - last < 86400000) {
    const hours = Math.ceil((86400000 - (Date.now() - last)) / 3600000);
    note.textContent = `Una key cada 24 horas. Probá de nuevo en ${hours} h.`;
    return;
  }
  const key = await generateKey(1);
  localStorage.setItem(STORE.key, key);
  localStorage.setItem(STORE.key + '_device', deviceID());
  localStorage.setItem(STORE.key + '_at', String(Date.now()));
  localStorage.setItem(STORE.lastKey, String(Date.now()));
  $('fk-key').textContent = key;
  $('fk-result').classList.remove('hidden');
  note.textContent = '';
}

function copyGeneratedKey() {
  copyText($('fk-key').textContent, null);
  const note = $('fk-note');
  note.textContent = 'Key copiada. Pegala en la app.';
}

async function revokeKey() {
  const key = localStorage.getItem(STORE.key);
  if (!key) return;
  const revoked = JSON.parse(localStorage.getItem(STORE.revoked) || '[]');
  if (!revoked.includes(key)) revoked.push(key);
  localStorage.setItem(STORE.revoked, JSON.stringify(revoked));
  localStorage.removeItem(STORE.key);
  $('fk-result').classList.add('hidden');
  renderProfile();
}

async function renderProfile() {
  const stored = localStorage.getItem(STORE.key);
  const name = JSON.parse(localStorage.getItem(STORE.profile) || '{}').name;
  $('profile-input').value = name || '';
  $('profile-name').textContent = name || 'Invitado';
  $('profile-avatar').textContent = (name || 'P').charAt(0).toUpperCase();

  if (!stored) {
    $('p-status').textContent = 'inactive';
    $('p-key').textContent = '—';
    $('p-activation').textContent = '—';
    $('p-expiry').textContent = '—';
    $('p-device').textContent = deviceID().slice(0, 12);
    return;
  }
  const result = await checkKey(stored);
  $('p-status').textContent = result.active ? `granted${result.legacy ? ' · legacy' : ''}` : result.reason;
  $('p-key').textContent = stored.slice(0, 4) + '…' + stored.slice(-4);
  $('p-activation').textContent = result.status || '—';
  $('p-expiry').textContent = result.expiry
    ? result.expiry.toISOString().slice(0, 10) : '—';
  $('p-device').textContent = deviceID().slice(0, 12);
}

function saveProfile() {
  const name = $('profile-input').value.trim().slice(0, 24) || 'Invitado';
  localStorage.setItem(STORE.profile, JSON.stringify({ name }));
  renderProfile();
}

// ---- static UI ------------------------------------------------------------

function renderSign(group) {
  $('sig-list').innerHTML = SIG_LINKS[group].map(([name, href]) =>
    `<a class="sig-row" href="${href}"><span><strong>${name}</strong><small>IPA firmada</small></span><span class="go">Instalar →</span></a>`
  ).join('');
}

const FK_TEXT = {
  es: { heading: 'Acceso gratuito de 24 horas', sub: 'Genera una clave de 24 horas vinculada a este iPhone.', s1: 'Configura tu nombre en Mi perfil.', s2: 'Instala el perfil en este iPhone para registrar el UDID.', s3: 'Toca Generar key. Aparece sola y se copia.', go: 'Generar key' },
  en: { heading: 'Free access for 24 hours', sub: 'Generate a 24-hour key bound to this iPhone.', s1: 'Set your name in My profile.', s2: 'Install the profile on this iPhone to register the UDID.', s3: 'Tap Generate key. It appears and copies itself.', go: 'Generate key' },
  sq: { heading: 'Qasje falas 24 orë', sub: 'Gjenero një çelës 24-orësh të lidhur me këtë iPhone.', s1: 'Vendos emrin tënd te Profili.', s2: 'Instalo profilin në iPhone për të regjistruar UDID-in.', s3: 'Shtyp Gjenero key. Shfaqet vetë dhe kopjohet.', go: 'Gjenero key' }
};

function setLang(lang) {
  const t = FK_TEXT[lang] || FK_TEXT.es;
  $('fk-heading').textContent = t.heading;
  $('fk-sub').textContent = t.sub;
  $('fk-s1').textContent = t.s1;
  $('fk-s2').textContent = t.s2;
  $('fk-s3').textContent = t.s3;
  $('fk-go').textContent = t.go;
  document.querySelectorAll('.fk-lang button').forEach(b => b.classList.toggle('active', b.dataset.lang === lang));
}

function initWave() {
  const canvas = $('wave');
  const ctx = canvas.getContext('2d');
  let t = 0;
  function resize() { canvas.width = innerWidth; canvas.height = innerHeight; }
  function draw() {
    resize();
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    for (let layer = 0; layer < 3; layer++) {
      ctx.beginPath();
      for (let x = 0; x <= canvas.width; x += 18) {
        const y = canvas.height * (0.72 + layer * 0.06)
          + Math.sin(x / 140 + t + layer) * (24 + layer * 12);
        x === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y);
      }
      ctx.strokeStyle = `rgba(${90 + layer * 25}, ${90 + layer * 10}, 220, ${0.12 - layer * 0.025})`;
      ctx.lineWidth = 1;
      ctx.stroke();
    }
    t += 0.012;
    requestAnimationFrame(draw);
  }
  draw();
}

document.addEventListener('DOMContentLoaded', () => {
  $('stat-visits').textContent = inc('visits');
  $('m-visits').textContent = $('stat-visits').textContent;
  $('stat-downloads').textContent = localStorage.getItem(STORE.downloads) || 0;
  $('m-downloads').textContent = $('stat-downloads').textContent;

  document.querySelectorAll('.nav-link').forEach(b => b.addEventListener('click', () => switchTab(b.dataset.tab)));
  document.querySelectorAll('.sig-tab').forEach(b => b.addEventListener('click', () => {
    document.querySelectorAll('.sig-tab').forEach(x => x.classList.toggle('active', x === b));
    renderSign(b.dataset.sig);
  }));
  document.querySelectorAll('.fk-lang button').forEach(b => b.addEventListener('click', () => setLang(b.dataset.lang)));
  renderSign('esign');
  setLang('es');
  renderProfile();
  initWave();
});
