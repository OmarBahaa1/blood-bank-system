/* ui.js — سلوك بصري فقط (القائمة الجانبية + حقل تاريخ الميلاد وتنبيه العمر).
   لا يغيّر أي route أو اسم حقل؛ لو فشل أي جزء الصفحة تفضل شغالة بدونه. */
(function () {
  'use strict';

  var root = document.documentElement;
  var STORE_KEY = 'wateen.sidebar';

  function store(get, val) {
    try {
      if (get) return window.localStorage.getItem(STORE_KEY);
      window.localStorage.setItem(STORE_KEY, val);
    } catch (e) { /* التخزين غير متاح: نكمل بدون حفظ */ }
    return null;
  }

  /* ---------- 1) طي القائمة الجانبية (الشاشات الكبيرة) ---------- */
  function setupSidebarCollapse() {
    var btn = document.getElementById('sidebarCollapse');
    if (!btn) return;
    var label = btn.querySelector('.side-text');

    function sync() {
      var collapsed = root.classList.contains('sb-collapsed');
      var text = collapsed ? 'توسيع القائمة' : 'طي القائمة';
      btn.setAttribute('aria-expanded', collapsed ? 'false' : 'true');
      btn.setAttribute('aria-label', text);
      btn.setAttribute('title', text);
      if (label) label.textContent = text;
    }

    btn.addEventListener('click', function () {
      var collapsed = root.classList.toggle('sb-collapsed');
      store(false, collapsed ? 'collapsed' : 'expanded');
      sync();
    });
    sync();
    // تفعيل الحركة بعد أول رسم فقط، حتى لا تتحرك القائمة عند فتح الصفحة
    window.requestAnimationFrame(function () {
      window.requestAnimationFrame(function () { root.classList.add('sb-ready'); });
    });
  }

  /* ---------- 2) الدرج الجانبي (أقل من 992px) ---------- */
  function setupDrawer() {
    var panel = document.getElementById('appSidebar');
    if (!panel || !window.bootstrap || !window.bootstrap.Offcanvas) return;
    var toggles = document.querySelectorAll('[data-bs-target="#appSidebar"][data-bs-toggle="offcanvas"]');

    function setExpanded(v) {
      for (var i = 0; i < toggles.length; i++) toggles[i].setAttribute('aria-expanded', v ? 'true' : 'false');
    }
    panel.addEventListener('shown.bs.offcanvas', function () { setExpanded(true); });
    panel.addEventListener('hidden.bs.offcanvas', function () { setExpanded(false); });

    // إغلاق الدرج عند اختيار رابط (Esc والخلفية واحتجاز التركيز من Bootstrap نفسه)
    panel.addEventListener('click', function (e) {
      var link = e.target.closest ? e.target.closest('a[href]') : null;
      if (!link || !panel.classList.contains('show')) return;
      var inst = window.bootstrap.Offcanvas.getInstance(panel);
      if (inst) inst.hide();
    });
  }

  /* ---------- 3) تاريخ الميلاد: يوم / شهر / سنة على الموبايل ---------- */
  var MONTHS = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
                'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];

  function pad(n) { return (n < 10 ? '0' : '') + n; }
  function toLatinDigits(s) {
    return s.replace(/[٠-٩]/g, function (c) { return String(c.charCodeAt(0) - 0x0660); });
  }

  /* شرط العمر للتبرع: 18-60 سنة مكتملة (نفس شرط السيرفر). الواجهة للتنبيه فقط، والسيرفر هو المرجع. */
  var AGE_MIN = 18, AGE_MAX = 60;
  var DOB_TXT = {
    missing: 'أدخل تاريخ ميلاد المتبرع.',
    invalid: 'تاريخ الميلاد غير صحيح. أدخل تاريخًا حقيقيًا (اليوم والشهر والسنة).',
    future: 'تاريخ الميلاد لم يأتِ بعد. راجع التاريخ.'
  };

  function ageWords(n) {
    if (n === 0) return 'أقل من سنة';
    if (n === 1) return 'سنة واحدة';
    if (n === 2) return 'سنتان';
    var r = n % 100;
    return n + (r >= 3 && r <= 10 ? ' سنوات' : ' سنة');
  }

  // y/mo/dd لتاريخ حقيقي؛ العمر بالسنوات المكتملة حتى اليوم (من تاريخ الجهاز، بدون سنة ثابتة)
  function checkAge(y, mo, dd) {
    var t = new Date();
    var ty = t.getFullYear(), tm = t.getMonth() + 1, td = t.getDate();
    if ((y - ty || mo - tm || dd - td) > 0) return { ok: false, text: DOB_TXT.future };
    var age = ty - y - ((tm < mo || (tm === mo && td < dd)) ? 1 : 0);
    if (age < AGE_MIN || age > AGE_MAX) {
      return {
        ok: false,
        text: 'المتبرع عمره ' + ageWords(age) + '. التبرع بالدم متاح من عمر 18 إلى 60 سنة حفاظًا على سلامة المتبرع. تأكد من تاريخ الميلاد.'
      };
    }
    return { ok: true, text: 'عمر المتبرع ' + ageWords(age) + '، مناسب للتبرع ✓' };
  }

  // state: 'ok' | 'bad' — الحالة مكتوبة نصاً + أيقونة، وليست باللون فقط
  function setDobMsg(msg, text, state) {
    msg.textContent = text || '';
    msg.hidden = !text;
    msg.classList.toggle('is-ok', !!text && state === 'ok');
    msg.classList.toggle('is-bad', !!text && state !== 'ok');
  }

  function el(tag, attrs, text) {
    var e = document.createElement(tag);
    for (var k in attrs) if (Object.prototype.hasOwnProperty.call(attrs, k)) e.setAttribute(k, attrs[k]);
    if (text != null) e.textContent = text;
    return e;
  }

  function enhanceBirthDate(wrap) {
    var real = wrap.querySelector('input[type="date"]');
    if (!real || real.getAttribute('data-split') === '1') return;
    real.setAttribute('data-split', '1');

    var baseId = real.id || 'birth';
    var label = wrap.querySelector('label[for="' + real.id + '"]');
    var maxYear = new Date().getFullYear();
    var MIN_YEAR = 1900;

    var group = el('div', { 'class': 'dob-split', role: 'group' });
    if (label) {
      if (!label.id) label.id = baseId + '_label';
      group.setAttribute('aria-labelledby', label.id);
    }
    var msgId = baseId + '_msg';
    var hintId = real.getAttribute('aria-describedby');
    var describedBy = hintId ? hintId + ' ' + msgId : msgId;

    var day = el('select', { 'class': 'form-select', id: baseId + '_day', 'aria-label': 'يوم الميلاد', required: '', 'aria-describedby': describedBy });
    day.appendChild(new Option('اليوم', ''));
    for (var d = 1; d <= 31; d++) day.appendChild(new Option(String(d), String(d)));

    var month = el('select', { 'class': 'form-select', id: baseId + '_month', 'aria-label': 'شهر الميلاد', required: '', 'aria-describedby': describedBy });
    month.appendChild(new Option('الشهر', ''));
    for (var m = 0; m < 12; m++) month.appendChild(new Option(MONTHS[m], String(m + 1)));

    var year = el('input', {
      'class': 'form-control', id: baseId + '_year', type: 'text', inputmode: 'numeric',
      autocomplete: 'off', maxlength: '4', pattern: '[0-9٠-٩]{4}', placeholder: 'السنة',
      'aria-label': 'سنة الميلاد (4 أرقام)', required: '', 'aria-describedby': describedBy, dir: 'ltr'
    });

    var msg = el('div', { 'class': 'dob-msg', id: msgId, 'aria-live': 'polite' });
    msg.hidden = true;

    group.appendChild(day); group.appendChild(month); group.appendChild(year);

    // الحقل الأصلي يفضل في النموذج بنفس الاسم والـ id، لكنه مخفي؛
    // نشيل required منه لأن حقل مخفي (display:none) مايقدرش ياخد التركيز عند الخطأ،
    // والتحقق بقى على الحقول الظاهرة الثلاثة.
    real.hidden = true;
    real.removeAttribute('required');
    real.setAttribute('tabindex', '-1');
    real.setAttribute('aria-hidden', 'true');
    real.parentNode.insertBefore(group, real.nextSibling);
    group.parentNode.insertBefore(msg, group.nextSibling);
    if (label) label.setAttribute('for', day.id);

    // قيمة موجودة مسبقاً (مثلاً المتصفح استرجعها) نوزعها على الأجزاء
    var pre = /^(\d{4})-(\d{2})-(\d{2})$/.exec(real.value || '');
    if (pre) { year.value = pre[1]; month.value = String(+pre[2]); day.value = String(+pre[3]); }

    var touched = false;

    // يرجّع {ok, value, field, text}
    function evaluate() {
      // الأرقام العربية الهندية (٠-٩) تُقرأ كما هي رقمياً؛ لا نعدّل ما كتبه المستخدم في الحقل
      var dv = day.value, mv = month.value, yv = toLatinDigits(year.value.trim());
      if (!dv || !mv || !yv) {
        var first = !dv ? day : (!mv ? month : year);
        return { ok: false, field: first, text: 'أكمل تاريخ الميلاد: اليوم والشهر والسنة.', incomplete: true };
      }
      if (!/^\d{4}$/.test(yv)) {
        return { ok: false, field: year, text: 'اكتب السنة بأربعة أرقام، مثل 1995.' };
      }
      var y = +yv, mo = +mv, dd = +dv;
      if (y < MIN_YEAR) {
        return { ok: false, field: year, text: 'السنة يجب أن تكون بين ' + MIN_YEAR + ' و ' + maxYear + '.' };
      }
      var dt = new Date(Date.UTC(y, mo - 1, dd));
      if (dt.getUTCFullYear() !== y || dt.getUTCMonth() !== mo - 1 || dt.getUTCDate() !== dd) {
        return { ok: false, field: day, text: 'هذا التاريخ غير موجود في التقويم (مثل 31 فبراير). راجع اليوم والشهر.' };
      }
      // تاريخ كامل وحقيقي: نعرض العمر فوراً (مناسب أو خارج 18-60 أو تاريخ لم يأتِ)
      var a = checkAge(y, mo, dd);
      if (!a.ok) return { ok: false, field: year, text: a.text };
      return { ok: true, value: yv + '-' + pad(mo) + '-' + pad(dd), text: a.text };
    }

    function apply(showMsg) {
      var r = evaluate();
      [day, month, year].forEach(function (f) { f.setCustomValidity(''); f.removeAttribute('aria-invalid'); });
      if (r.ok) {
        real.value = r.value;
        setDobMsg(msg, r.text, 'ok');
        group.classList.remove('is-invalid');
        return r;
      }
      real.value = ''; // لا نكتب أي تاريخ ناقص أو غير صحيح
      // رسالة عربية واحدة على الحقل المسؤول (تظهر أيضاً في فقاعة المتصفح عند الإرسال)؛
      // باقي الحقول الفاضية يمنعها required
      r.field.setCustomValidity(r.text);
      if (showMsg) {
        r.field.setAttribute('aria-invalid', 'true');
        group.classList.add('is-invalid');
        setDobMsg(msg, r.text, 'bad');
      } else {
        setDobMsg(msg, '');
      }
      return r;
    }

    function onEdit() {
      var r = evaluate();
      apply(touched || (r.ok === false && !r.incomplete));
    }

    day.addEventListener('change', onEdit);
    month.addEventListener('change', onEdit);
    year.addEventListener('input', onEdit);
    [day, month, year].forEach(function (f) {
      f.addEventListener('blur', function () {
        if (day.value || month.value || year.value) { touched = true; apply(true); }
      });
      // عند محاولة الإرسال: المتصفح يركّز أول حقل غير صالح، ونعرض الرسالة جنبه
      f.addEventListener('invalid', function () { touched = true; apply(true); });
    });

    var form = real.form;
    if (form) {
      // حماية أخيرة: لو المتصفح ما منعش الإرسال لأي سبب، نمنعه نحن ونركّز الحقل
      form.addEventListener('submit', function (e) {
        touched = true;
        var r = apply(true);
        if (!r.ok) {
          e.preventDefault();
          r.field.focus();
        }
      });
    }
    apply(false);
  }

  /* حقل التاريخ الأصلي (الشاشات الكبيرة): نفس رسالة العمر الحية ونفس منع الإرسال */
  function enhanceNativeDate(wrap) {
    var real = wrap.querySelector('input[type="date"]');
    if (!real || real.getAttribute('data-age') === '1') return;
    real.setAttribute('data-age', '1');

    var msgId = (real.id || 'birth') + '_msg';
    var msg = el('div', { 'class': 'dob-msg', id: msgId, 'aria-live': 'polite' });
    msg.hidden = true;
    real.parentNode.insertBefore(msg, real.nextSibling);
    var hintId = real.getAttribute('aria-describedby');
    real.setAttribute('aria-describedby', hintId ? hintId + ' ' + msgId : msgId);

    var touched = false;

    function evaluate() {
      var v = real.value || '';
      var m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(v);
      if (!m) {
        // المتصفح يعطي قيمة فارغة طالما التاريخ ناقص (badInput)
        var bad = !!v || !!(real.validity && real.validity.badInput);
        return { ok: false, text: bad ? DOB_TXT.invalid : DOB_TXT.missing, incomplete: true };
      }
      return checkAge(+m[1], +m[2], +m[3]);
    }

    function apply(showMsg) {
      var r = evaluate();
      real.setCustomValidity(r.ok ? '' : r.text);
      if (r.ok) {
        real.removeAttribute('aria-invalid');
        setDobMsg(msg, r.text, 'ok');
      } else if (showMsg || !r.incomplete) {
        real.setAttribute('aria-invalid', 'true');
        setDobMsg(msg, r.text, 'bad');
      } else {
        real.removeAttribute('aria-invalid');
        setDobMsg(msg, '');
      }
      return r;
    }

    function onEdit() { apply(touched); }
    real.addEventListener('input', onEdit);
    real.addEventListener('change', onEdit);
    real.addEventListener('blur', function () {
      if (real.value || (real.validity && real.validity.badInput)) touched = true;
      apply(touched);
    });
    real.addEventListener('invalid', function () { touched = true; apply(true); });

    if (real.form) {
      real.form.addEventListener('submit', function (e) {
        touched = true;
        if (!apply(true).ok) {
          e.preventDefault();
          real.focus();
        }
      });
    }
    apply(false);
  }

  function setupBirthDate() {
    var wraps = document.querySelectorAll('[data-dob-split]');
    if (!wraps.length) return;
    var mq = window.matchMedia ? window.matchMedia('(pointer: coarse), (max-width: 991.98px)') : null;
    // الموبايل: يوم/شهر/سنة. الشاشات الكبيرة بالماوس: يبقى حقل التاريخ الأصلي مع نفس فحص العمر
    var split = !!(mq && mq.matches);
    for (var i = 0; i < wraps.length; i++) {
      try {
        if (split) enhanceBirthDate(wraps[i]); else enhanceNativeDate(wraps[i]);
      } catch (e) { if (window.console) console.warn('dob:', e); }
    }
  }

  function init() {
    try { setupSidebarCollapse(); } catch (e) { if (window.console) console.warn('sidebar:', e); }
    try { setupDrawer(); } catch (e) { if (window.console) console.warn('drawer:', e); }
    setupBirthDate();
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init); else init();
})();
