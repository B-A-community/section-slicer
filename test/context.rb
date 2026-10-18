# Объект внутри открытой (редактируемой) поднятой и повёрнутой группы:
# отметки и раскладка — в мировых координатах, сечения ложатся на Z = 0.
load File.expand_path('helper.rb', __dir__)

module SSTest
  m = model
  clean
  holder = m.entities.add_group
  holder.name = 'SS_TEST_context'
  cube = box(holder.entities, 0, 0, 0, 1000, 2000, 1000)
  holder.transformation = Geom::Transformation.translation([0, -8000 * MM, 2000 * MM]) *
                          Geom::Transformation.rotation(ORIGIN, Z_AXIS, 90.degrees)
  session = nil
  begin
    m.active_path = [holder]
    m.selection.clear
    m.selection.add(cube)
    session = SS::Session.start(m)

    check('object box is in world coordinates inside an open context') do
      near session.object_box[2], 2000 * MM, 1e-6, 'zmin'
      near session.object_box[5], 3000 * MM, 1e-6, 'zmax'
      near session.object_box[3] - session.object_box[0], 2000 * MM, 1e-6, 'rotated width'
    end

    check('sections built from an open context lie at world Z = 0 right of the object') do
      session.typed_elevation('2500')
      session.build
      container = session.container
      assert container.parent == holder.definition, 'created in the active context'
      groups = container.entities.grep(Sketchup::Group)
      assert groups.size == 1, "groups #{groups.size}"
      world = holder.transformation * container.transformation * groups[0].transformation
      pts = groups[0].entities.grep(Sketchup::Face).first.vertices.map { |v| v.position.transform(world) }
      assert pts.all? { |p| p.z.abs < 1e-6 }, "world z #{pts.map(&:z).uniq}"
      assert pts.map(&:x).min > session.object_box[3], 'right of the object'
      near m2(groups[0].entities.grep(Sketchup::Face).first.area), 2.0, 1e-9, 'area 1 × 2 m'
    end
  ensure
    session.close if session
    m.active_path = nil
    clean
  end
  puts "context: #{passed} checks passed"
end
