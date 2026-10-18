# Геометрия сечений: кубы, отверстия, острова, вложенность, разрывы.
load File.expand_path('helper.rb', __dir__)

module SSTest
  m = model
  m.start_operation('SS geometry test', true)
  root = m.entities.add_group
  root.name = 'SS_TEST_geometry'
  slicer = SS::Slicer
  section_of = lambda do |group, z_mm|
    faces = slicer.collect(group.definition.entities, group.transformation)
    box = slicer.bounds(faces)
    slicer.section(faces, z_mm * MM, box[5])
  end
  area_of = lambda do |section|
    tmp = root.entities.add_group
    result = slicer.fill(tmp.entities, section)
    areas = result[:faces].map { |f| m2(f.area) }
    loops = result[:faces].map { |f| f.loops.size }
    normals = result[:faces].map { |f| f.normal.z.round(6) }
    gaps = result[:chains].size
    tmp.erase!
    [areas, loops, normals, gaps]
  end

  begin
    cube = box(root.entities, 0, 0, 0, 1000, 1000, 1000)
    check('cube 1x1x1 m at +500 gives one face 1.00 m2') do
      areas, loops, normals, gaps = area_of.call(section_of.call(cube, 500))
      assert areas.size == 1, "faces: #{areas.size}"
      near areas[0], 1.0, 1e-9, 'area'
      assert loops == [1] && normals == [1.0] && gaps.zero?, "loops #{loops} normals #{normals} gaps #{gaps}"
    end

    check('cut exactly at bottom and top vertices still gives the plan') do
      [0, 1000].each do |z|
        areas, = area_of.call(section_of.call(cube, z))
        assert areas.size == 1, "z=#{z} faces: #{areas.size}"
        near areas[0], 1.0, 1e-9, "z=#{z} area"
      end
    end

    check('section outside the object is empty') do
      assert section_of.call(cube, 1500).empty?, 'expected empty above'
    end

    holed = root.entities.add_group
    outer = holed.entities.add_face([[0, 0, 0], [2000, 0, 0], [2000, 2000, 0], [0, 2000, 0]].map { |p| Geom::Point3d.new(*p.map { |v| v * MM }) })
    inner = holed.entities.add_face([[750, 750, 0], [1250, 750, 0], [1250, 1250, 0], [750, 1250, 0]].map { |p| Geom::Point3d.new(*p.map { |v| v * MM }) })
    inner.erase!
    outer.reverse! if outer.normal.z < 0
    outer.pushpull(1000 * MM)
    holed.transformation = Geom::Transformation.translation([3000 * MM, 0, 0])
    check('through hole becomes a cut-out: one face, area = outer - inner') do
      areas, loops, = area_of.call(section_of.call(holed, 400))
      assert areas.size == 1, "faces: #{areas.size}"
      assert loops == [2], "loops: #{loops}"
      near areas[0], 4.0 - 0.25, 1e-9, 'area'
    end

    island = root.entities.add_group
    [[0, 3000, 0, 3000], [500, 2500, 500, 2500], [1250, 1750, 1250, 1750]].each_with_index do |(x0, x1, y0, y1), i|
      pts = [[x0, y0, 0], [x1, y0, 0], [x1, y1, 0], [x0, y1, 0]].map { |p| Geom::Point3d.new(*p.map { |v| v * MM }) }
      island.entities.add_face(pts)
    end
    # Кольцо и остров: верхняя грань кольца и колонна выдавливаются,
    # грань между ними удаляется — двор с колонной посередине.
    faces = island.entities.grep(Sketchup::Face).sort_by { |f| -f.area }
    ring, yard, column = faces
    yard.erase!
    [ring, column].each { |f| f.reverse! if f.normal.z < 0; f.pushpull(3000 * MM) }
    island.transformation = Geom::Transformation.translation([0, 3000 * MM, 0])
    check('courtyard with a column: ring with hole plus separate column face') do
      areas, loops, = area_of.call(section_of.call(island, 1500))
      assert areas.size == 2, "faces: #{areas.size}"
      near areas.max, 9.0 - 4.0, 1e-9, 'ring area'
      near areas.min, 0.25, 1e-9, 'column area'
      assert loops.sort == [1, 2], "loops: #{loops}"
    end

    nested = root.entities.add_group
    inner_box = box(nested.entities, 0, 0, 0, 1000, 1000, 1000)
    inner_box.transformation = Geom::Transformation.scaling(ORIGIN, 2, 1, 1) # 2 × 1 м
    second = box(nested.entities, 0, 0, 0, 1000, 1000, 1000)
    second.transformation = Geom::Transformation.translation([2000 * MM, 0, 0]) *
                            Geom::Transformation.rotation(ORIGIN, Z_AXIS, 0) # вплотную справа
    deeper = nested.entities.add_group
    rotated = box(deeper.entities, 0, 0, 0, 1000, 1000, 1000)
    rotated.transformation = Geom::Transformation.translation([0, 3000 * MM, 0]) *
                             Geom::Transformation.rotation(ORIGIN, Z_AXIS, 30.degrees)
    nested.transformation = Geom::Transformation.translation([7000 * MM, 0, 2000 * MM])
    check('nested groups at any depth with scale, rotation and touching walls merge') do
      sec = section_of.call(nested, 2500)
      areas, loops, = area_of.call(sec)
      # Две соприкасающиеся коробки сливаются в 3 × 1 м; повёрнутая копия — 2 м².
      assert areas.size == 2, "faces: #{areas.size} #{areas}"
      near areas.max, 3.0, 1e-9, 'merged area'
      near areas.min, 1.0 * 1.0 * 1.0, 1e-9, 'rotated copy keeps definition size'
      assert loops == [1, 1], "loops: #{loops}"
    end

    open_box = box(root.entities, 0, 0, 0, 1000, 1000, 1000)
    open_box.entities.grep(Sketchup::Face).find { |f| f.normal.x.abs > 0.99 && f.bounds.min.x.abs < 1e-6 }.erase!
    open_box.transformation = Geom::Transformation.translation([0, -3000 * MM, 0])
    check('missing wall leaves edges, no face, and reports a gap') do
      sec = section_of.call(open_box, 500)
      assert sec.gaps?, 'expected gaps'
      areas, _, _, gaps = area_of.call(sec)
      assert areas.empty? && gaps == 1, "areas #{areas} gaps #{gaps}"
    end

    step = root.entities.add_group
    lower = step.entities.add_face([[0, 0, 0], [2000, 0, 0], [2000, 1000, 0], [0, 1000, 0]].map { |p| Geom::Point3d.new(*p.map { |v| v * MM }) })
    lower.reverse! if lower.normal.z < 0
    lower.pushpull(1000 * MM)
    top = step.entities.grep(Sketchup::Face).find { |f| f.normal.z > 0.99 }
    step.entities.add_line(Geom::Point3d.new(1000 * MM, 0, 1000 * MM), Geom::Point3d.new(1000 * MM, 1000 * MM, 1000 * MM))
    half = step.entities.grep(Sketchup::Face).select { |f| f.normal.z > 0.99 }.min_by { |f| f.bounds.min.x }
    half.pushpull(1000 * MM)
    step.transformation = Geom::Transformation.translation([-4000 * MM, 0, 0])
    check('cut at the step level shows the upper storey (h + epsilon)') do
      areas, = area_of.call(section_of.call(step, 1000))
      near areas.sum, 1.0, 1e-9, 'upper storey'
      areas, = area_of.call(section_of.call(step, 999))
      near areas.sum, 2.0, 1e-9, 'lower storey'
      areas, = area_of.call(section_of.call(step, 2000))
      near areas.sum, 1.0, 1e-9, 'roof level'
    end

    cylinder = root.entities.add_group
    circle = cylinder.entities.add_circle(ORIGIN, Z_AXIS, 500 * MM, 48)
    disc = cylinder.entities.add_face(circle)
    disc.reverse! if disc.normal.z < 0
    disc.pushpull(800 * MM)
    cylinder.transformation = Geom::Transformation.translation([-4000 * MM, -3000 * MM, 0])
    check('cylinder section keeps polygon area and collapses nothing') do
      areas, = area_of.call(section_of.call(cylinder, 300))
      expected = 0.5 * 48 * 0.5**2 * Math.sin(2 * Math::PI / 48)
      near areas[0], expected, 1e-6, 'polygon area'
    end

    walls = root.entities.add_group
    # Стены отдельными группами: угол внахлёст, T-примыкание к середине,
    # и короб, целиком вложенный в другой.
    box(walls.entities, 0, 0, 0, 5000, 300, 3000)          # A: 5 × 0,3
    box(walls.entities, 4700, 0, 0, 300, 4000, 3000)       # B: внахлёст с A на углу
    box(walls.entities, 2000, 300, 0, 200, 2000, 3000)     # C: T-примыкание к A
    box(walls.entities, 1000, 50, 0, 500, 200, 3000)       # D: целиком внутри A
    walls.transformation = Geom::Transformation.translation([0, 12_000 * MM, 0])
    check('overlapping, T-junction and contained walls merge into one plan contour') do
      areas, loops, = area_of.call(section_of.call(walls, 1500))
      expected = 5.0 * 0.3 + 0.3 * 4.0 - 0.3 * 0.3 + 0.2 * 2.0
      assert areas.size == 1, "faces: #{areas.size} #{areas}"
      near areas[0], expected, 1e-9, 'union area'
      assert loops == [1], "loops: #{loops}"
    end

    check('SketchUp 2021 path (add_face + erase) gives the same faces as EntitiesBuilder') do
      [[island, 1500], [holed, 400], [walls, 1500]].each do |group, z|
        sec = section_of.call(group, z)
        tmp = root.entities.add_group
        slicer.fill_by_splitting(tmp.entities, sec)
        legacy = tmp.entities.grep(Sketchup::Face).map { |f| [m2(f.area).round(9), f.loops.size] }.sort
        tmp.erase!
        modern = area_of.call(sec).values_at(0, 1).transpose.map { |a, l| [a.round(9), l] }.sort
        assert legacy == modern, "#{group.name}: #{legacy} vs #{modern}"
      end
    end

    check('solid check: nested solids count as a body, a missing wall does not') do
      assert slicer.solid?(cube.definition.entities), 'cube'
      assert slicer.solid?(nested.definition.entities), 'group of nested solids'
      assert !slicer.solid?(open_box.definition.entities), 'open box'
    end

    check('slanted roof: section of a prism through sloped faces') do
      prism = root.entities.add_group
      pts = [[0, 0, 0], [2000, 0, 0], [1000, 0, 1000]].map { |p| Geom::Point3d.new(*p.map { |v| v * MM }) }
      tri = prism.entities.add_face(pts)
      tri.pushpull(1000 * MM)
      prism.transformation = Geom::Transformation.translation([0, -6000 * MM, 0])
      areas, = area_of.call(section_of.call(prism, 500))
      near areas.sum, 1.0, 1e-9, 'half-height width 1 m × depth 1 m'
    end
  ensure
    m.abort_operation
  end
  puts "geometry: #{passed} checks passed"
end
