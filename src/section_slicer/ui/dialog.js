// Copyright 2026 B&A community. Licensed under Apache License 2.0.
// Окно Section Slicer: состояние приходит из Ruby целиком через SS.render,
// действия уходят через sketchup.<callback>.

var SS = (function () {
  'use strict';

  var ICON_PIN = '<svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6">' +
    '<circle cx="8" cy="8" r="4.5"/><path d="M8 0.5v4M8 11.5v4M0.5 8h4M11.5 8h4"/></svg>';
  var state = null;
  var stringsApplied = false;
  var selectedPid = null;

  function $(id) { return document.getElementById(id); }
  function call(name) {
    var args = Array.prototype.slice.call(arguments, 1);
    if (window.sketchup && window.sketchup[name]) window.sketchup[name].apply(window.sketchup, args);
  }
  function esc(text) {
    return String(text == null ? '' : text).replace(/[&<>"]/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c];
    });
  }
  function t(key) { return (state && state.strings[key]) || key; }

  function applyStrings() {
    document.querySelectorAll('[data-t]').forEach(function (el) { el.textContent = t(el.getAttribute('data-t')); });
    document.querySelectorAll('[data-tip]').forEach(function (el) { el.title = t(el.getAttribute('data-tip')); });
    stringsApplied = true;
  }

  function toast(text) {
    var el = $('toast');
    el.textContent = text;
    el.classList.add('on');
    clearTimeout(toast.timer);
    toast.timer = setTimeout(function () { el.classList.remove('on'); }, 2100);
  }

  function renderHeader() {
    var o = state.object;
    var info = o.name || '';
    if (o.mode === 'slice') info = o.kind + ' «' + info + '»';
    $('object').textContent = info;
    $('unit').textContent = state.unit;
    document.body.classList.toggle('report', o.mode === 'report');
    $('notices').innerHTML = state.notices.map(function (n) {
      return '<div class="notice ' + esc(n.kind) + '">' + esc(n.text) + '</div>';
    }).join('');
    $('tool-state').textContent = o.mode === 'slice' && !state.tool_active ? t('tool_off') : '';
  }

  function renderPlanes() {
    var focus = document.activeElement;
    var focusKey = focus && focus.dataset && focus.dataset.field ? focus.dataset.id + ':' + focus.dataset.field : null;

    $('pending').textContent = state.pending === 'new' ? t('pending_new')
      : state.pending === 'rebind' ? t('pending_rebind') : '';
    $('add').classList.toggle('on', state.pending === 'new');
    $('undo').disabled = !state.can_undo;

    var body = $('planes').querySelector('tbody');
    if (!state.planes.length) {
      body.innerHTML = '<tr class="empty"><td colspan="5">' + esc(t('no_planes')) + '</td></tr>';
    } else {
      body.innerHTML = state.planes.map(function (p) {
        var cls = [p.active ? 'active' : '', p.inside ? '' : 'out', p.rebinding ? 'rebinding' : ''].join(' ');
        return '<tr class="' + cls + '" data-id="' + p.id + '">' +
          '<td class="n">' + (p.number || '—') + '</td>' +
          '<td><input class="z" data-id="' + p.id + '" data-field="z" value="' + esc(p.z) + '" title="' + esc(p.z_label) + '"></td>' +
          '<td><input class="step" data-id="' + p.id + '" data-field="step" value="' + esc(p.step) + '" placeholder="0"></td>' +
          '<td><input class="count" type="number" min="0" step="1" data-id="' + p.id + '" data-field="count" value="' + p.count + '"></td>' +
          '<td class="act">' +
          '<button class="icon" data-act="rebind" data-id="' + p.id + '" title="' + esc(t('rebind')) + '">' + ICON_PIN + '</button> ' +
          '<button class="icon" data-act="remove" data-id="' + p.id + '" title="' + esc(t('remove')) + '">✕</button>' +
          '</td></tr>';
      }).join('');
    }
    var lv = state.levels;
    $('levels').textContent = state.planes.length
      ? t('levels').replace('{n}', lv.inside) + (lv.out ? ' · ' + t('levels_out').replace('{n}', lv.out) : '')
      : '';
    $('build').disabled = !lv.inside;

    if (focusKey) {
      var parts = focusKey.split(':');
      var el = body.querySelector('input[data-id="' + parts[0] + '"][data-field="' + parts[1] + '"]');
      if (el) { el.focus(); if (el.select) el.select(); }
    }
  }

  function renderSettings() {
    var s = state.settings;
    ['gap', 'columns'].forEach(function (k) { if (document.activeElement !== $(k)) $(k).value = Math.round(s[k]); });
    ['mode', 'area_unit', 'decimal'].forEach(function (k) { $(k).value = s[k]; });
    $('columns').disabled = s.mode !== 'grid';
  }

  function renderTable() {
    var box = $('results');
    var tb = state.table;
    $('copy').disabled = $('csv').disabled = !tb;
    if (!tb) {
      box.innerHTML = '<div class="placeholder">' + esc(t('no_results')) + '</div>';
      return;
    }
    var numeric = [false, true, false, true, true, false];
    var html = '<table><thead><tr>' + tb.header.map(function (h, i) {
      return '<th' + (numeric[i] ? ' class="num"' : '') + '>' + esc(h) + '</th>';
    }).join('') + '</tr></thead><tbody>';
    tb.rows.forEach(function (r) {
      var sel = r.pid != null && r.pid === selectedPid ? ' sel' : '';
      html += '<tr class="' + r.kind + sel + '"' + (r.pid != null ? ' data-pid="' + r.pid + '"' : '') + '>';
      r.cells.forEach(function (c, i) {
        var content = esc(c);
        if (i === 5 && r.kind !== 'grand' && c !== '') {
          var kind = r.kind === 'gap' || /разрыв/.test(c) ? 'warn' : (r.kind === 'total' && /пусто/.test(c) ? 'bad' : 'ok');
          content = '<span class="pill ' + kind + '">' + esc(c) + '</span>';
        }
        html += '<td' + (numeric[i] ? ' class="num"' : '') + '>' + content + '</td>';
      });
      html += '</tr>';
    });
    box.innerHTML = html + '</tbody></table>';
  }

  function render(next) {
    state = next;
    if (!stringsApplied) applyStrings();
    renderHeader();
    renderPlanes();
    renderSettings();
    renderTable();
  }

  // TSV → HTML для буфера: Excel берёт HTML и не трогает текстовые ячейки.
  function tsvToHtml(tsv) {
    var rows = tsv.replace(/\r\n$/, '').split('\r\n').map(function (line) { return line.split('\t'); });
    return '<table>' + rows.map(function (cells, r) {
      return '<tr>' + cells.map(function (c) {
        var m = /^="(.*)"$/.exec(c);
        var tag = r === 0 ? 'th' : 'td';
        return m ? '<' + tag + ' style="mso-number-format:\'\\@\'">' + esc(m[1]) + '</' + tag + '>'
          : '<' + tag + '>' + esc(c) + '</' + tag + '>';
      }).join('') + '</tr>';
    }).join('') + '</table>';
  }

  // Основной путь — Ruby (WinAPI / pbcopy), он не зависит от фокуса окна.
  function copyTable() {
    if (state && state.table) call('copy');
  }

  function copied(ok) {
    if (ok) toast(t('copied'));
    else copyInBrowser();
  }

  function copyInBrowser() {
    if (!state || !state.table) return;
    var text = state.table.tsv;
    var html = tsvToHtml(text);
    var done = function () { toast(t('copied')); };
    var fallback = function () {
      var handler = function (e) {
        e.clipboardData.setData('text/plain', text);
        e.clipboardData.setData('text/html', html);
        e.preventDefault();
      };
      document.addEventListener('copy', handler);
      var area = document.createElement('textarea');
      area.value = text;
      document.body.appendChild(area);
      area.select();
      var ok = false;
      try { ok = document.execCommand('copy'); } catch (err) { ok = false; }
      document.body.removeChild(area);
      document.removeEventListener('copy', handler);
      if (ok) done();
    };
    try {
      if (navigator.clipboard && window.ClipboardItem) {
        navigator.clipboard.write([new ClipboardItem({
          'text/plain': new Blob([text], { type: 'text/plain' }),
          'text/html': new Blob([html], { type: 'text/html' })
        })]).then(done, fallback);
        return;
      }
    } catch (err) { /* старый CEF — ниже фолбэк */ }
    fallback();
  }

  function sendSettings() {
    call('settings', JSON.stringify({
      gap: parseFloat($('gap').value) || 0,
      mode: $('mode').value,
      columns: parseInt($('columns').value, 10) || 1,
      area_unit: $('area_unit').value,
      decimal: $('decimal').value
    }));
  }

  function commitField(input) {
    var id = input.dataset.id;
    var field = input.dataset.field;
    if (field === 'z') call('set_z', id, input.value);
    else {
      var row = input.closest('tr');
      call('set_array', id, row.querySelector('input.step').value, row.querySelector('input.count').value);
    }
  }

  function bind() {
    $('add').addEventListener('click', function () { call('add'); });
    $('undo').addEventListener('click', function () { call('undo'); });
    $('build').addEventListener('click', function () { call('build'); });
    $('cancel').addEventListener('click', function () { call('cancel'); });
    $('copy').addEventListener('click', copyTable);
    $('csv').addEventListener('click', function () { call('export_csv'); });
    ['gap', 'mode', 'columns', 'area_unit', 'decimal'].forEach(function (k) {
      $(k).addEventListener('change', sendSettings);
    });

    var planes = $('planes');
    planes.addEventListener('click', function (e) {
      var btn = e.target.closest('button[data-act]');
      if (btn) { call(btn.dataset.act, btn.dataset.id); return; }
      var row = e.target.closest('tr[data-id]');
      if (row && !row.classList.contains('active')) call('select', row.dataset.id);
    });
    planes.addEventListener('change', function (e) {
      if (e.target.dataset && e.target.dataset.field) commitField(e.target);
    });
    planes.addEventListener('keydown', function (e) {
      if (e.key === 'Enter' && e.target.dataset && e.target.dataset.field) { e.preventDefault(); e.target.blur(); }
    });

    $('results').addEventListener('click', function (e) {
      var row = e.target.closest('tr[data-pid]');
      if (!row) return;
      selectedPid = parseInt(row.dataset.pid, 10);
      document.querySelectorAll('#results tr.sel').forEach(function (r) { r.classList.remove('sel'); });
      row.classList.add('sel');
      call('select_entity', selectedPid);
    });

    document.addEventListener('keydown', function (e) {
      var inField = /INPUT|SELECT|TEXTAREA/.test(document.activeElement.tagName);
      if (e.key === 'Escape') call('escape');
      else if ((e.ctrlKey || e.metaKey) && (e.key === 'z' || e.key === 'Z' || e.key === 'я') && !inField) { e.preventDefault(); call('undo'); }
      else if (e.key === 'Enter' && !inField) call('build');
      else if ((e.key === 'n' || e.key === 'N' || e.key === 'т') && !inField) call('add');
      else if (e.key === 'Delete' && !inField) {
        var active = state && state.planes.filter(function (p) { return p.active; })[0];
        if (active) call('remove', active.id);
      }
    });
  }

  bind();
  document.addEventListener('DOMContentLoaded', function () { call('ready'); });
  if (document.readyState !== 'loading') call('ready');

  return { render: render, copy: copyTable, copied: copied, tsvToHtml: tsvToHtml };
})();
