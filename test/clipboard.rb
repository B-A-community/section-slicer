# Шаг 1 проверки буфера: строит сечения демо-здания и нажимает
# «Копировать» в настоящем окне. Шаг 2 — test/excel_paste.ps1.
load File.expand_path('helper.rb', __dir__)

module SSTest
  m = model
  clean
  building = m.entities.add_group
  building.name = 'SS_TEST_clip'
  [[0, false], [3000, true]].each do |z0, hole|
    g = building.entities.add_group
    face = g.entities.add_face([[0, 0, z0], [10_000, 0, z0], [10_000, 8000, z0], [0, 8000, z0]].map { |p| Geom::Point3d.new(*p.map { |v| v * MM }) })
    if hole
      inner = g.entities.add_face([[4000, 3000, z0], [6000, 3000, z0], [6000, 5000, z0], [4000, 5000, z0]].map { |p| Geom::Point3d.new(*p.map { |v| v * MM }) })
      inner.erase!
    end
    face.reverse! if face.normal.z < 0
    face.pushpull(3000 * MM)
  end
  m.selection.clear
  m.selection.add(building)
  session = SS::Session.start(m)
  session.update_settings('decimal' => ',', 'area_unit' => 'm2')
  session.typed_elevation('1500')
  last = session.planes.last
  session.set_array(last.id, '3000', '1')
  session.build
  $ss_clip_expected = session.table[:rows].last[:cells][3]
  puts "expected grand total #{$ss_clip_expected}"
end
