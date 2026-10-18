# Вторая половина interactive.rb: результат клика в настоящем HtmlDialog
# доступен только после того, как SketchUp обработал очередь событий.
load File.expand_path('helper.rb', __dir__)

module SSTest
  session = $ss_interactive_session
  begin
    check('dialog: button click reached Ruby, DOM shows planes, no horizontal overflow') do
      probe = $ss_probe
      assert probe, 'probe callback did not arrive'
      assert session.pending == :new, "pending #{session.pending.inspect}"
      assert probe['addOn'] && probe['pending'] == SS.t(:ui_pending_new), probe.inspect
      assert probe['rows'] == session.planes.planes.size, "rows #{probe['rows']}"
      assert probe['title'] == SS.t(:ui_title) && probe['build'] == SS.t(:ui_build), 'strings applied'
      assert !probe['overflowX'], "horizontal overflow at #{probe['width']}px"
      puts "  dialog inner size #{probe['width']} x #{probe['height']}"
    end
  ensure
    session.close if session
    clean
    $ss_interactive_session = nil
  end
end
