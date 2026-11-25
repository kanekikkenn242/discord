/* Dope distribution portal — local demo.
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

/// Empty by default (local demo). Set window.DOPE_API in config.js to the
/// deployed worker; then keys become bound to the real iPhone UDID.
const API_BASE = String(window.DOPE_API || "").replace(/\/$/, "");

function udidToken() {
  let t = localStorage.getItem('px_udid_token');
  if (!t) {
    t = Array.from(crypto.getRandomValues(new Uint8Array(12)))
      .map(b => b.toString(16).padStart(2, '0')).join('').toUpperCase();
    localStorage.setItem('px_udid_token', t);
  }
  return t;
}

function inc(name) {
  const n = Number(localStorage.getItem(STORE[name]) || 0) + 1;
  localStorage.setItem(STORE[name], String(n));
  return n;
}

function trackDownload() {
  const n = inc('downloads');
  ['stat-downloads', 'stat-downloads-hero', 'stat-downloads-big'].forEach(id => {
    const el = $(id);
    if (el) el.textContent = n;
  });
}

const TAB_IDS = { download: 'download', sign: 'sign', installer: 'sign', freekey: 'freekey', profile: 'profile' };
const NAV_IDS = { download: 'download', sign: 'installer', installer: 'installer', freekey: 'freekey', profile: 'profile' };

function switchTab(tab) {
  tab = TAB_IDS[tab] || 'download';
  document.querySelectorAll('.tab-content').forEach(el => el.classList.remove('active'));
  const content = $('content-' + tab);
  if (content) content.classList.add('active');
  document.querySelectorAll('.lp-nav-link').forEach(el => el.classList.remove('active'));
  const nav = $('nav-link-' + (NAV_IDS[tab] || tab));
  if (nav) nav.classList.add('active');
  if (tab === 'profile') renderProfile();
  const area = $('content-area');
  if (area) area.scrollIntoView({ behavior: 'smooth', block: 'start' });
}

function toggleMenu() {
  const menu = $('user-menu');
  const backdrop = $('config-backdrop');
  const btn = $('nav-menu-btn');
  if (!menu) return;
  const open = !menu.classList.contains('is-open');
  menu.classList.toggle('hidden', !open);
  menu.classList.toggle('is-open', open);
  if (backdrop) backdrop.classList.toggle('hidden', !open);
  if (btn) btn.setAttribute('aria-expanded', open ? 'true' : 'false');
  document.body.classList.toggle('lp-lock', open);
}

function closeMenu() {
  const menu = $('user-menu');
  const backdrop = $('config-backdrop');
  const btn = $('nav-menu-btn');
  if (menu) { menu.classList.remove('is-open'); menu.classList.add('hidden'); }
  if (backdrop) backdrop.classList.add('hidden');
  if (btn) btn.setAttribute('aria-expanded', 'false');
  document.body.classList.remove('lp-lock');
}

function openTabFromMenu(tab) { closeMenu(); switchTab(tab); }

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

const FREE_KEY_WINDOW = 86400000; // 24 h

/// Only one free key per device in any 24-hour window, and never a second key
/// while the current one is still valid.
async function freeKeyGate() {
  const stored = localStorage.getItem(STORE.key);
  if (stored) {
    const result = await checkKey(stored);
    if (result.active) {
      const until = result.expiry ? result.expiry.toISOString().slice(0, 10) : '—';
      return { ok: false, message: `Ya tenés una key activa hasta ${until}. No se puede generar otra.` };
    }
  }
  const last = Number(localStorage.getItem(STORE.lastKey) || 0);
  if (last) {
    const left = FREE_KEY_WINDOW - (Date.now() - last);
    if (left > 0) {
      const hours = Math.max(1, Math.ceil(left / 3600000));
      return { ok: false, message: `Una key cada 24 horas. Probá de nuevo en ${hours} h.` };
    }
  }
  return { ok: true };
}

async function refreshFreeKeyGate() {
  const gate = await freeKeyGate();
  const note = $('fk-note');
  const button = $('fk-go');
  if (note && !gate.ok) note.textContent = gate.message;
  if (button) button.disabled = !gate.ok;
  return gate;
}

async function generateFreeKey() {
  const note = $('fk-note');
  const gate = await freeKeyGate();
  if (!gate.ok) {
    note.textContent = gate.message;
    return;
  }
  let key = await generateKey(1);
  let serverIssued = false;

  // With the gateway deployed, the key is issued by the server and bound to
  // the real UDID captured by the MDM check-in. Local generation is the
  // offline fallback.
  if (API_BASE) {
    try {
      const res = await fetch(`${API_BASE}/api/key`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ t: udidToken() })
      });
      const data = await res.json();
      if (data.key) { key = data.key; serverIssued = true; }
      else if (data.error) note.textContent = data.error;
    } catch (e) { /* keep local key */ }
  }

  localStorage.setItem(STORE.key, key);
  localStorage.setItem(STORE.key + '_device', deviceID());
  localStorage.setItem(STORE.key + '_at', String(Date.now()));
  localStorage.setItem(STORE.lastKey, String(Date.now()));
  $('fk-key').textContent = key;
  $('fk-result').classList.remove('hidden');
  if (!note.textContent) {
    note.textContent = serverIssued
      ? 'Key lidhur me UDID-in e iPhone-it'
      : 'Key gjeneruar lokalisht (serveri nuk është konfiguruar).';
  }
  await refreshFreeKeyGate();
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
  const name = JSON.parse(localStorage.getItem(STORE.profile) || '{}').name || 'Invitado';
  const input = $('profile-name-input');
  if (input) input.value = name;
  const label = $('profile-name');
  if (label) label.textContent = name;
  const heading = $('profile-heading');
  if (heading) heading.textContent = name;
  const avatar = $('profile-avatar');
  if (avatar) avatar.textContent = name.charAt(0).toUpperCase();
  const menuAvatar = $('menu-avatar');
  if (menuAvatar) menuAvatar.textContent = name.charAt(0).toUpperCase();

  const set = (id, value) => { const el = $(id); if (el) el.textContent = value; };
  if (!stored) {
    set('p-status', 'inactive'); set('p-key', '—'); set('p-activation', '—');
    set('p-expiry', '—'); set('p-device', deviceID().slice(0, 12));
    return;
  }
  const result = await checkKey(stored);
  set('p-status', result.active ? `granted${result.legacy ? ' · legacy' : ''}` : result.reason);
  set('p-key', stored.slice(0, 4) + '…' + stored.slice(-4));
  set('p-activation', result.status || '—');
  set('p-expiry', result.expiry ? result.expiry.toISOString().slice(0, 10) : '—');
  set('p-device', deviceID().slice(0, 12));
}

function saveProfile() {
  const input = $('profile-name-input');
  const name = (input ? input.value : '').trim().slice(0, 24) || 'Invitado';
  localStorage.setItem(STORE.profile, JSON.stringify({ name }));
  const note = $('profile-note');
  if (note) note.textContent = 'Guardado';
  renderProfile();
}

// ---- static UI ------------------------------------------------------------

const SIG_META = {
  esign: ['02', 'ESign', 'Firma el IPA dentro de ESign. Si una no abre, prueba la siguiente.'],
  ksign: ['03', 'KSign', 'Firma el IPA dentro de KSign. Si una no abre, prueba la siguiente.'],
  scarlet: ['04', 'Scarlet', 'Firma el IPA dentro de Scarlet. Si una no abre, prueba la siguiente.'],
  gbox: ['05', 'GBox', 'Firma el IPA dentro de GBox. Si una no abre, prueba la siguiente.']
};

function renderSign(group) {
  const meta = SIG_META[group] || SIG_META.esign;
  const rows = SIG_LINKS[group].map(([name, href]) =>
    `<a class="sig-row" href="${href}"><span class="sig-row__meta"><span class="sig-row__name">${name}</span><span class="sig-row__org">IPA firmada · Dope</span></span><span class="sig-row__go">Instalar</span></a>`
  ).join('');
  const host = $('sig-list');
  if (host) host.innerHTML =
    `<section class="sig-group"><header class="sig-group__head"><span class="sig-group__n">${meta[0]}</span><div><h3 class="sig-group__t">${meta[1]}</h3><p class="sig-group__d">${meta[2]}</p></div><span class="sig-group__count">${SIG_LINKS[group].length} apps</span></header><div class="sig-list">${rows}</div></section>`;
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
  const canvas = $('waveCanvas');
  if (!canvas) return;
  const ctx = canvas.getContext('2d');
  let t = 0;
  function resize() { canvas.width = canvas.offsetWidth || innerWidth; canvas.height = canvas.offsetHeight || 260; }
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
  const visits = inc('visits');
  ['stat-visits', 'stat-visits-hero', 'stat-visits-big'].forEach(id => {
    const el = $(id); if (el) el.textContent = visits;
  });
  const downloads = Number(localStorage.getItem(STORE.downloads) || 0);
  ['stat-downloads', 'stat-downloads-hero', 'stat-downloads-big'].forEach(id => {
    const el = $(id); if (el) el.textContent = downloads;
  });

  document.querySelectorAll('.lp-nav-link').forEach(b => b.addEventListener('click', () => switchTab(b.dataset.tab)));
  document.querySelectorAll('.sig-tab').forEach(b => b.addEventListener('click', () => {
    document.querySelectorAll('.sig-tab').forEach(x => {
      const on = x === b;
      x.classList.toggle('active', on);
      x.setAttribute('aria-selected', on ? 'true' : 'false');
    });
    renderSign(b.dataset.sig);
  }));
  document.querySelectorAll('.fk-lang button').forEach(b => b.addEventListener('click', () => setLang(b.dataset.lang)));

  const nav = document.querySelector('.lp-head');
  window.addEventListener('scroll', () => {
    if (nav) nav.classList.toggle('is-stuck', window.scrollY > 20);
  }, { passive: true });

  const items = Array.prototype.slice.call(document.querySelectorAll('.reveal'));
  if (items.length && 'IntersectionObserver' in window &&
      !window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
    const io = new IntersectionObserver(entries => {
      entries.forEach(entry => {
        if (!entry.isIntersecting) return;
        entry.target.classList.add('is-in');
        io.unobserve(entry.target);
      });
    }, { threshold: 0.1, rootMargin: '0px 0px -6% 0px' });
    items.forEach(el => io.observe(el));
  } else {
    items.forEach(el => el.classList.add('is-in'));
  }

  renderSign('esign');
  setLang('es');
  renderProfile();
  refreshFreeKeyGate();
  initWave();

  if (API_BASE) {
    const token = udidToken();
    const links = [$('fk-profile'), $('profile-install-link')].filter(Boolean);
    links.forEach(link => { link.href = `${API_BASE}/udid/web?l=es&t=${token}`; });
    fetch(`${API_BASE}/api/udid?t=${token}`)
      .then(r => r.json())
      .then(data => {
        if (data.udid && $('fk-note')) {
          $('fk-note').textContent = `iPhone i regjistruar · ${data.udid.slice(0, 4)}…${data.udid.slice(-4)}`;
        }
      })
      .catch(() => {});
  }
});
