# Шаг 2: окно уже загружено — клик по кнопке «Добавить» и проба DOM.
module SSTest
  session = $ss_interactive_session
  raise 'run interactive.rb first' unless session && session.dialog.visible?
  session.dialog.execute_script(<<~JS)
    document.getElementById('add').click();
    setTimeout(function () {
      var q = function (s) { return document.querySelectorAll(s).length; };
      sketchup.test_probe(JSON.stringify({
        rows: q('#planes tbody tr[data-id]'), pending: document.getElementById('pending').textContent,
        addOn: document.getElementById('add').classList.contains('on'),
        title: document.querySelector('header .title').textContent,
        build: document.getElementById('build').textContent,
        overflowX: document.documentElement.scrollWidth > window.innerWidth,
        height: window.innerHeight, width: window.innerWidth
      }));
    }, 300);
  JS
  puts 'dialog click queued'
end
