# Настоящий viewport: InputPoint привязывается к вершине, ребру и грани,
# отрисовка плоскостей, клавиши инструмента, открытый контекст группы.
load File.expand_path('helper.rb', __dir__)

module SSTest
  m = model
  view = m.active_view
  old_camera = Sketchup::Camera.new(view.camera.eye, view.camera.target, view.camera.up)
  clean
  holder = m.entities.add_group
  holder.name = 'SS_TEST_mouse'
  cube = box(holder.entities, 0, 0, 0, 1000, 1000, 1000)
  holder.transformation = Geom::Transformation.translation([20_000 * MM, 0, 0])
  m.selection.clear
  m.selection.add(holder)
  view.camera = Sketchup::Camera.new(Geom::Point3d.new(20_000 * MM + 3000 * MM, -2500 * MM, 2200 * MM),
                                     Geom::Point3d.new(20_000 * MM + 500 * MM, 500 * MM, 500 * MM), Z_AXIS)
  view.refresh
  session = SS::Session.start(m)
  tool = session.tool
  click = lambda do |point|
    s = view.screen_coords(point)
    tool.onMouseMove(0, s.x.round, s.y.round, view)
    hover = tool.hover_z
    tool.onLButtonDown(0, s.x.round, s.y.round, view)
    hover
  end
  world = ->(x, y, z) { Geom::Point3d.new(20_000 * MM + x * MM, y * MM, z * MM) }

  begin
    check('click on a vertex fixes the plane at its Z') do
      click.call(world.call(1000, 0, 1000))
      near session.planes.last.z, 1000 * MM, 1e-6, 'vertex z'
    end

    check('click on an edge midpoint and on a face') do
      session.begin_new
      z = click.call(world.call(1000, 0, 500))
      near z, 500 * MM, 2 * MM, 'edge midpoint'
      session.begin_new
      z = click.call(world.call(1000, 400, 300))
      near z, 300 * MM, 30 * MM, 'point on the face'
      assert session.planes.planes.size == 3, 'three planes'
    end

    check('click without N does nothing; N, Delete, Esc and Ctrl+Z') do
      count = session.planes.planes.size
      click.call(world.call(1000, 0, 0))
      assert session.planes.planes.size == count, 'no plane without pending'
      tool.onKeyDown(78, 0, 0, view)
      assert session.pending == :new, 'N starts a new plane'
      tool.onCancel(0, view)
      assert session.pending.nil?, 'Esc cancels waiting'
      tool.onKeyDown(VK_DELETE, 0, 0, view)
      assert session.planes.planes.size == count - 1, 'Delete removes the active plane'
      tool.onCancel(0, view)
      assert session.planes.planes.size == count, 'Esc undoes the removal'
      tool.onKeyDown(VK_DELETE, 0, 0, view)
      tool.onCancel(2, view) # Ctrl+Z SketchUp при активном инструменте, построения не было
      assert session.planes.planes.size == count, 'Ctrl+Z undoes the removal'
    end

    check('rebind a plane by clicking a new point') do
      plane = session.planes.planes.first
      session.rebind(plane.id)
      click.call(world.call(0, 0, 0))
      near session.planes.find(plane.id).z, 0, 1e-6, 'rebound to the base'
    end

    check('draw: planes, labels and extents do not touch the model') do
      before = m.entities.size
      session.begin_new
      s = view.screen_coords(world.call(1000, 1000, 1000))
      tool.onMouseMove(0, s.x.round, s.y.round, view)
      tool.draw(view)
      ext = tool.getExtents
      assert ext.width > 1000 * MM && ext.height > 1000 * MM, 'extents include the 10% margin'
      frame = session.frame
      near frame[2] - frame[0], 1200 * MM, 1e-6, 'plane is bbox + 10% each side'
      assert m.entities.size == before, 'no geometry created by preview'
      session.escape
    end

    check('inside an open group, clicks still read world Z') do
      original = holder.transformation
      lifted = Geom::Transformation.translation([0, 0, 2000 * MM]) * original
      holder.transformation = lifted
      m.active_path = [holder]
      session.refresh_geometry
      session.begin_new
      z = click.call(Geom::Point3d.new(20_000 * MM + 1000 * MM, 0, 3000 * MM))
      m.active_path = nil
      holder.transformation = original
      session.refresh_geometry
      near z, 3000 * MM, 5 * MM, 'world z of a vertex of a lifted group opened for editing'    end

    check('real HtmlDialog is open; queue button click and DOM probe') do
      dialog = session.dialog
      assert dialog.visible?, 'dialog visible'
      $ss_probe = nil
      dialog.add_action_callback('test_probe') { |_, json| $ss_probe = JSON.parse(json) }
      # Страница загрузится только после выхода из этого запроса;
      # клик и проба DOM — в interactive_dialog.rb.
    end
  ensure
    m.active_view.camera = old_camera
  end
  $ss_interactive_session = session
  puts "interactive: #{passed} checks passed (dialog probe continues in interactive_check.rb)"
end
