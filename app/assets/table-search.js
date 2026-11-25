/* table-search.js : بحث وفلترة إضافية لجداول المخزون والطلبات (إضافة فقط)
   لا يغيّر أي ملف قديم ولا يلمس قاعدة البيانات. لو حصل أي خطأ بيتوقف بهدوء. */
(function () {
  'use strict';

  // ---------- القسم 1: CSS صغير للإخفاء ----------
  // بنستخدم class خاص بينا بدل style.display، عشان فلتر الحالة القديم
  // (statusFilter) ما يلغيش بحثنا، وبحثنا ما يلغيش فلتره.
  var style = document.createElement('style');
  style.textContent = '.ws-hide{display:none!important}' +
    '.ws-bar{display:flex;flex-wrap:wrap;gap:8px;align-items:center;padding:12px 16px;margin:0;' +
    'border-bottom:1px solid #e2e8f0}' +
    '.ws-bar input[type=search],.ws-bar select{font:inherit;font-size:14px;padding:6px 10px;border:1px solid #94a3b8;' +
    'border-radius:6px;background:#fff;color:#1e293b;min-width:0;max-width:100%}' +
    '.ws-bar input[type=search]{flex:1 1 220px;max-width:320px}' +
    '.ws-bar select{flex:0 1 auto}' +
    '.ws-bar button{font:inherit;font-size:14px;padding:6px 12px;border:1px solid #94a3b8;border-radius:6px;' +
    'background:#f1f5f9;color:#1e293b;cursor:pointer}' +
    '.ws-bar label{font-size:14px;color:#1e293b;display:inline-flex;align-items:center;gap:6px;cursor:pointer;margin:0}' +
    '.ws-count{font-size:14px;color:#475569;font-weight:600}' +
    '.ws-empty{padding:14px;text-align:center;color:#475569;font-size:15px}';
  document.head.appendChild(style);

  // ---------- القسم 2: دوال مساعدة ----------
  function norm(s) {
    // توحيد النص: حروف صغيرة، حذف التشكيل، وتوحيد الهمزات والياء والتاء المربوطة
    return String(s || '').toLowerCase()
      .replace(/[ً-ْٰـ]/g, '')
      .replace(/[أإآ]/g, 'ا').replace(/ى/g, 'ي').replace(/ة/g, 'ه').trim();
  }
  function colIndex(table, words) {
    var ths = table.querySelectorAll('thead th');
    for (var i = 0; i < ths.length; i++) {
      var t = norm(ths[i].textContent);
      for (var j = 0; j < words.length; j++) if (t.indexOf(norm(words[j])) !== -1) return i;
    }
    return -1;
  }
  function cellText(row, i) {
    return i < 0 || !row.cells[i] ? '' : row.cells[i].textContent.trim();
  }
  // إصلاح (c): صف "لا توجد أكياس / الطلبات مكتملة" (خلية واحدة بـ colspan) مش صف بيانات
  function isDataRow(r) {
    return !(r.cells.length === 1 && r.cells[0].colSpan > 1);
  }
  function el(tag, attrs) {
    var e = document.createElement(tag);
    for (var k in attrs) e.setAttribute(k, attrs[k]);
    return e;
  }

  // ---------- القسم 3: الدالة الرئيسية ----------
  // cfg: { typeWords, placeholder, skipWords, extra: [{build(), test(row, ctl)}] }
  function enhance(table, cfg) {
    if (!table || table.getAttribute('data-ws') === '1') return;
    var tbody = table.tBodies[0];
    if (!tbody) return;
    table.setAttribute('data-ws', '1');

    var typeCol = colIndex(table, cfg.typeWords);
    // إصلاح (b): عمود مستبعد من البحث النصي (زي عمود "إجراء الصرف")
    var skipCol = cfg.skipWords ? colIndex(table, cfg.skipWords) : -1;
    var rows = function () {
      return Array.prototype.slice.call(tbody.rows).filter(isDataRow);
    };
    function rowText(r) {
      var parts = [];
      for (var i = 0; i < r.cells.length; i++) if (i !== skipCol) parts.push(r.cells[i].textContent);
      return norm(parts.join(' '));
    }

    // شريط البحث
    var bar = el('div', { 'class': 'ws-bar' });
    var q = el('input', { type: 'search', placeholder: cfg.placeholder, 'aria-label': 'بحث' });
    var typeSel = el('select', { 'aria-label': 'فلتر الفصيلة' });
    typeSel.appendChild(new Option('كل الفصائل', ''));
    var seen = {};
    rows().forEach(function (r) {
      var t = cellText(r, typeCol);
      if (t && !seen[t]) { seen[t] = 1; typeSel.appendChild(new Option(t, t)); }
    });
    var clear = el('button', { type: 'button' });
    clear.textContent = 'مسح البحث';
    var count = el('span', { 'class': 'ws-count', 'aria-live': 'polite' });
    bar.appendChild(q); bar.appendChild(typeSel);

    var extras = (cfg.extra || []).map(function (x) {
      var ctl = x.build(table); bar.appendChild(ctl.node); return { ctl: ctl, test: x.test };
    });
    bar.appendChild(clear); bar.appendChild(count);

    // الشريط جوه الكارت فوق الجدول: قبل غلاف .table-responsive (لو موجود) عشان ما يتحركش مع السكرول الأفقي
    var anchor = table.parentNode && table.parentNode.classList &&
      table.parentNode.classList.contains('table-responsive') ? table.parentNode : table;
    anchor.parentNode.insertBefore(bar, anchor);

    // رسالة "لا توجد نتائج": عنصر خارج الجدول (مش صف)، عشان فلتر الحالة القديم
    // بيعدّل كل صفوف tbody وكان هيخفي أي صف إضافي.
    var empty = el('div', { 'data-ws-empty': '1', 'class': 'ws-hide ws-empty' });
    empty.textContent = 'لا توجد نتائج';
    anchor.parentNode.insertBefore(empty, anchor.nextSibling);

    // الأعداد والرسالة بتعتمد على اللي ظاهر فعلاً (بحثنا + فلتر الحالة القديم)
    function refresh() {
      var all = rows(), shown = 0;
      all.forEach(function (r) { if (window.getComputedStyle(r).display !== 'none') shown++; });
      empty.classList.toggle('ws-hide', shown !== 0 || all.length === 0);
      count.textContent = 'ظاهر ' + shown + ' من ' + all.length;
    }
    function apply() {
      var words = norm(q.value).split(/\s+/).filter(Boolean);
      var tv = typeSel.value, all = rows();
      all.forEach(function (r) {
        var text = rowText(r), ok = true;
        words.forEach(function (w) { if (text.indexOf(w) === -1) ok = false; });
        if (ok && tv && cellText(r, typeCol) !== tv) ok = false;
        if (ok) extras.forEach(function (x) { if (!x.test(r, x.ctl)) ok = false; });
        r.classList.toggle('ws-hide', !ok);
      });
      refresh();
    }
    // أي فلتر تاني في الصفحة (زي statusFilter القديم) بيغيّر الصفوف: نحدّث العدّاد بعده
    document.addEventListener('change', function () { setTimeout(refresh, 0); });
    q.addEventListener('input', apply);
    typeSel.addEventListener('change', apply);
    extras.forEach(function (x) { x.ctl.node.addEventListener('change', apply); });
    // "مسح البحث" بيرجّع أدواتنا بس، ومش بيلمس statusFilter
    clear.addEventListener('click', function () {
      q.value = ''; typeSel.value = '';
      extras.forEach(function (x) { if (x.ctl.reset) x.ctl.reset(); });
      apply();
    });
    apply();
  }

  // ---------- القسم 4: المخزون (inventory) ----------
  // بحث نصي في كل الأعمدة (رقم الكيس، الفصيلة، المتبرع، مكان التخزين...)
  // + فصيلة + "ينتهي خلال 7 أيام".
  function setupInventory() {
    var table = document.getElementById('inventoryTable');
    if (!table) return;
    var daysCol = colIndex(table, ['المتبقي']);
    enhance(table, {
      typeWords: ['الفصيله', 'الفصيلة'],
      placeholder: 'ابحث: رقم الكيس، المتبرع، مكان التخزين...',
      extra: [{
        build: function () {
          var wrap = el('label', {});
          var cb = el('input', { type: 'checkbox' });
          wrap.appendChild(cb); wrap.appendChild(document.createTextNode('ينتهي خلال 7 أيام'));
          return { node: wrap, input: cb, reset: function () { cb.checked = false; } };
        },
        test: function (row, ctl) {
          if (!ctl.input.checked) return true;
          // إصلاح (a): نقرأ الرقم بإشارته؛ المقبول من 0 لـ 7 بس.
          // السالب (منتهي فعلاً) بيختفي، والأكياس اللي عمودها "-" مفيهاش رقم فتختفي.
          var m = cellText(row, daysCol).match(/-?\d+/);
          if (!m) return false;
          var n = parseInt(m[0], 10);
          return n >= 0 && n <= 7;
        }
      }]
    });
  }

  // ---------- القسم 5: طلبات المستشفيات (requests) ----------
  // بحث بالمستشفى/المدينة/الفصيلة + فلتر الأولوية (عاجل/عادي).
  function setupRequests() {
    var tables = document.querySelectorAll('table');
    var table = null;
    for (var i = 0; i < tables.length; i++) {
      if (colIndex(tables[i], ['المستشفي', 'المستشفى']) !== -1 && colIndex(tables[i], ['الاولويه', 'الأولوية']) !== -1) { table = tables[i]; break; }
    }
    if (!table || document.getElementById('inventoryTable')) return;
    var prioCol = colIndex(table, ['الاولويه', 'الأولوية']);
    enhance(table, {
      typeWords: ['الفصيله', 'الفصيلة'],
      placeholder: 'ابحث: المستشفى، المدينة، رقم الطلب...',
      // إصلاح (b): عمود "إجراء الصرف" (زرار "صرف (FEFO)") مش داخل في البحث
      skipWords: ['إجراء', 'اجراء'],
      extra: [{
        build: function () {
          var s = el('select', { 'aria-label': 'فلتر الأولوية' });
          s.appendChild(new Option('كل الأولويات', ''));
          s.appendChild(new Option('عاجل', 'عاجل'));
          s.appendChild(new Option('عادي', 'عادي'));
          return { node: s, input: s, reset: function () { s.value = ''; } };
        },
        test: function (row, ctl) {
          var v = ctl.input.value;
          if (!v) return true;
          return norm(cellText(row, prioCol)) === norm(v);
        }
      }]
    });
  }

  function init() {
    try { setupInventory(); setupRequests(); } catch (e) { if (window.console) console.warn('table-search:', e); }
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init); else init();
})();
