# Требование ТЗ: объект на 50 000 граней и 50 сечений — не дольше 30 секунд.
load File.expand_path('helper.rb', __dir__)

module SSTest
  m = model
  clean
  tower = m.entities.add_group
  tower.name = 'SS_TEST_perf'
  # Закрученная башня из треугольников: 250 по кругу × 100 по высоте × 2 = 50 000.
  around = 250
  rows = 100
  mesh = Geom::PolygonMesh.new((around * (rows + 1)) + 2, around * rows * 2 + around * 2)
  ring = lambda do |k|
    z = k * 60 * MM
    twist = k * 0.6.degrees
    r = (6000 + 1500 * Math.sin(k / 12.0)) * MM
    (0...around).map do |i|
      a = 2 * Math::PI * i / around + twist
      mesh.add_point(Geom::Point3d.new(r * Math.cos(a), r * Math.sin(a), z))
    end
  end
  ids = (0..rows).map { |k| ring.call(k) }
  rows.times do |k|
    around.times do |i|
      a = ids[k][i]
      b = ids[k][(i + 1) % around]
      c = ids[k + 1][(i + 1) % around]
      d = ids[k + 1][i]
      mesh.add_polygon(a, b, c)
      mesh.add_polygon(a, c, d)
    end
  end
  bottom = mesh.add_point(Geom::Point3d.new(0, 0, 0))
  top = mesh.add_point(Geom::Point3d.new(0, 0, rows * 60 * MM))
  around.times do |i|
    mesh.add_polygon(bottom, ids[0][(i + 1) % around], ids[0][i])
    mesh.add_polygon(top, ids[rows][i], ids[rows][(i + 1) % around])
  end
  tower.entities.fill_from_mesh(mesh, true, Geom::PolygonMesh::NO_SMOOTH_OR_HIDE)
  tower.transformation = Geom::Transformation.translation([0, 40_000 * MM, 0])
  face_count = tower.entities.grep(Sketchup::Face).size
  m.selection.clear
  m.selection.add(tower)

  session = SS::Session.start(m)
  begin
    first = session.planes.add(50 * MM)
    session.planes.set_array(first.id, 120 * MM, 49) # 50 отметок до 5930 мм
    session.instance_variable_set(:@pending, nil)
    check("#{face_count} faces × 50 sections in under 30 s") do
      assert face_count >= 50_000, "faces #{face_count}"
      started = Time.now
      session.build
      seconds = Time.now - started
      puts format('  built in %.2f s', seconds)
      assert seconds < 30, "too slow: #{seconds}"
      sections = session.report['sections']
      assert sections.size == 50 && sections.all? { |s| s['status'] == 'ok' }, sections.map { |s| s['status'] }.tally.inspect
      assert sections.all? { |s| s['contours'].size == 1 }, 'one closed contour per level'
    end
  ensure
    session.close if session
    clean
  end

  # Каркас из 400 стен-групп, пересекающихся в узлах сетки 20 × 20.
  frame = m.entities.add_group
  frame.name = 'SS_TEST_perf_walls'
  21.times do |i|
    box(frame.entities, i * 3000, 0, 0, 250, 60_000 + 250, 3000)
    box(frame.entities, 0, i * 3000, 0, 60_000 + 250, 250, 3000)
  end
  m.selection.clear
  m.selection.add(frame)
  session = SS::Session.start(m)
  begin
    first = session.planes.add(30 * MM)
    session.planes.set_array(first.id, 60 * MM, 49)
    session.instance_variable_set(:@pending, nil)
    check('42 crossing wall groups (441 overlaps) × 50 sections in under 30 s') do
      started = Time.now
      session.build
      seconds = Time.now - started
      puts format('  built in %.2f s', seconds)
      assert seconds < 30, "too slow: #{seconds}"
      sections = session.report['sections']
      assert sections.all? { |s| s['status'] == 'ok' }, sections.map { |s| s['status'] }.tally.inspect
      # Решётка: внешний контур с 400 отверстиями-ячейками — одна грань.
      assert sections.all? { |s| s['contours'].size == 1 }, sections.map { |s| s['contours'].size }.uniq.inspect
      expected = (60_250**2 - 400 * 2750**2) / 1.0e6
      sections.each { |s| near s['contours'][0]['area'] * 0.0254**2, expected, 1e-6, 'grid area' }
    end
  ensure
    session.close if session
    clean
  end
end
