# Сценарий целиком: плоскости и копии, построение, раскладка, таблица,
# атрибуты, отмена одним Undo. Настоящий Session, PlaneTool и операции модели.
load File.expand_path('helper.rb', __dir__)

module SSTest
  m = model
  old_selection = m.selection.to_a
  clean
  saved_settings = SS::Session.settings

  check('PlaneSet: array copies, merge within 0.1 mm, sort, numbering, out of bounds') do
    set = SS::PlaneSet.new(0, 9000 * MM)
    a = set.add(3000 * MM)
    set.set_array(a.id, 1000 * MM, 4)              # 3000, 4000 … 7000
    b = set.add(4000.05 * MM)                      # сливается с копией 4000
    c = set.add(1000 * MM)
    set.set_array(c.id, -1000 * MM, 3)             # 1000, 0, −1000, −2000
    levels = set.levels
    zs = levels.map { |l| (l.z / MM).round(2) }
    assert zs == [-2000, -1000, 0, 1000, 3000, 4000.05, 5000, 6000, 7000], "levels #{zs}"
    assert levels.select(&:inside).map(&:number) == (1..7).to_a, 'numbering 1..N inside'
    assert levels.count { |l| !l.inside } == 2, 'two copies below the object'
    assert levels.find { |l| (l.z / MM - 4000.05).abs < 1e-6 }.plane_id == b.id, 'original wins over copy'
    set.undo
    assert set.levels.size == 6, 'undo restores previous array'
  end

  check('units: elevation and number formatting') do
    assert SS::Units.format_elevation(3000 * MM, ',', group: true) == '+3 000', SS::Units.format_elevation(3000 * MM, ',', group: true)
    assert SS::Units.format_elevation(0, ',') == '±0', 'zero'
    assert SS::Units.format_elevation(-1200 * MM, ',') == '-1200', 'negative'
    near SS::Units.parse_length('1500'), 1500 * MM, 1e-9, 'parse mm'
    near SS::Units.parse_length('1,5m'), 1500 * MM, 1e-9, 'parse metres with comma'
    assert SS::Units.parse_length('abc').nil?, 'invalid text'
  end

  building = m.entities.add_group
  building.name = 'SS_TEST_building'
  # Три этажа по 3 м: 10 × 8 м, на втором — атриум 2 × 2 м насквозь.
  slab = lambda do |z0, hole|
    g = building.entities.add_group
    face = g.entities.add_face([[0, 0, z0], [10_000, 0, z0], [10_000, 8000, z0], [0, 8000, z0]].map { |p| Geom::Point3d.new(*p.map { |v| v * MM }) })
    if hole
      inner = g.entities.add_face([[4000, 3000, z0], [6000, 3000, z0], [6000, 5000, z0], [4000, 5000, z0]].map { |p| Geom::Point3d.new(*p.map { |v| v * MM }) })
      inner.erase!
    end
    face.reverse! if face.normal.z < 0
    face.pushpull(3000 * MM)
  end
  slab.call(0, false)
  slab.call(3000, true)
  slab.call(6000, false)
  building.transformation = Geom::Transformation.translation([2000 * MM, 1000 * MM, 0])
  m.selection.clear
  m.selection.add(building)

  session = SS::Session.start(m)
  begin
    check('session starts on one selected group and activates the plane tool') do
      assert session && session.instance == building, 'session'
      assert m.tools.active_tool_id != 0 && session.instance_variable_get(:@tool_active), 'tool active'
      assert session.pending == :new, 'waits for the first click'
      near session.object_box[3] - session.object_box[0], 10_000 * MM, 1e-6, 'bbox width'
    end

    check('refuses without exactly one group or component') do
      m.selection.clear
      orig = UI.method(:messagebox)
      shown = nil
      UI.define_singleton_method(:messagebox) { |text, *_| shown = text; IDOK }
      begin
        result = SS::Session.start(m)
      ensure
        UI.define_singleton_method(:messagebox, orig)
      end
      assert result.nil? && shown == SS.t(:select_one), "message #{shown.inspect}"
      assert SS::Session.current.equal?(session), 'running session untouched'
    end

    check('click elevation, VCB absolute and relative input, array of copies') do
      session.click_elevation(1500 * MM)               # первый этаж
      session.begin_new
      session.typed_elevation('4500')                  # абсолютно, мм
      session.begin_new
      session.typed_elevation('+3000')                 # от последней → 7500
      last = session.planes.last
      session.set_array(last.id, '-7500', '1')          # копия на 0
      session.begin_new
      session.typed_elevation('12000')                 # выше объекта
      zs = session.levels.map { |l| (l.z / MM).round(3) }
      assert zs == [0, 1500, 4500, 7500, 12_000], "levels #{zs}"
      assert session.levels.count(&:inside) == 4, 'four inside'
    end

    check('build: one undoable operation, grouped and laid out at Z=0 right of the model') do
      session.update_settings('gap' => 20, 'mode' => 'row', 'area_unit' => 'm2', 'decimal' => ',')
      before = m.entities.size
      report = session.build
      container = session.container
      assert report && container.valid?, 'built'
      assert m.entities.size == before + 1, 'single container added'
      assert container.name == 'Сечения · SS_TEST_building', container.name
      groups = container.entities.grep(Sketchup::Group)
      assert groups.size == 4, "groups #{groups.size}"
      names = groups.map(&:name)
      assert names == ['Сечение №1 · ±0', 'Сечение №2 · +1 500', 'Сечение №3 · +4 500', 'Сечение №4 · +7 500'], names.inspect
      xs = groups.map { |g| g.bounds.min.x }
      assert xs == xs.sort, 'left to right from the lowest'
      groups.each do |g|
        b = g.bounds.transform(container.transformation) rescue g.bounds
        near g.bounds.min.z, 0, 1e-9, 'Z = 0'
        near g.bounds.max.z, 0, 1e-9, 'flat'
        assert g.bounds.min.x > building.bounds.max.x, 'no overlap with the model'
        assert g.entities.all? { |e| e.is_a?(Sketchup::Face) || e.is_a?(Sketchup::Edge) }, 'only faces and edges'
        assert g.entities.grep(Sketchup::Face).all? { |f| f.normal.z > 0.999 }, 'faces up'
      end
      atrium = groups[2].entities.grep(Sketchup::Face)
      assert atrium.size == 1 && atrium[0].loops.size == 2, 'atrium is a cut-out'
      near m2(atrium[0].area), 80 - 4, 1e-6, 'atrium area'
      assert container.entities.grep(Sketchup::Text).size == 4, 'labels under sections'
      assert SS::AreaReport.load(container)['sections'].size == 4, 'report stored in attributes'
      assert building.entities.grep(Sketchup::Group).size == 3, 'source untouched'
    end

    check('table: rows per face, bold totals, grand total equals the sum, TSV parses') do
      table = session.table
      kinds = table[:rows].map { |r| r[:kind] }
      assert kinds == %w[face total face total face total face total grand], kinds.inspect
      tsv = SS::AreaReport.tsv(table)
      lines = tsv.split("\r\n").map { |l| l.split("\t", -1) }
      assert lines.all? { |l| l.size == 6 }, 'six columns everywhere'
      assert lines[0] == ['№ сечения', 'Отметка', '№ контура', 'Площадь, м²', 'Периметр, м', 'Статус'], lines[0].inspect
      assert lines[1] == ['1', '0', '="1.1"', '80,00', '36,00', 'OK'], lines[1].inspect
      faces = lines.select { |l| l[2].start_with?('="') }.map { |l| l[3].tr(',', '.').to_f }
      grand = lines.last[3].tr(',', '.').to_f
      near faces.sum, grand, 1e-9, 'grand total'
      near grand, 80 + 80 + 76 + 80, 1e-9, 'expected total'
      assert lines[7][1] == '7500', 'plain elevation for Excel'
      csv = SS::AreaReport.csv(table, 'decimal' => ',')
      assert csv.start_with?("﻿") && csv.include?(';'), 'CSV with BOM and semicolons'
    end

    check('row click selects the face; total row selects the section group') do
      pid = session.table[:rows].first[:pid]
      assert session.select_entity(pid), 'selected'
      face = m.selection.first
      assert face.is_a?(Sketchup::Face) && m.active_path.size == 2, "path #{m.active_path.inspect}"
      total = session.table[:rows].find { |r| r[:kind] == 'total' }
      assert session.select_entity(total[:pid]), 'total row'
      assert m.selection.first.is_a?(Sketchup::Group) && m.active_path.size == 1, 'total row selects the section group'
      m.active_path = nil
    end

    check('reopen the table from attributes') do
      reopened = SS::AreaReport.load(session.container)
      table = SS::AreaReport.table(reopened, 'decimal' => '.', 'area_unit' => 'cm2')
      assert table[:header][3] == 'Площадь, см²', table[:header][3]
      assert table[:rows].last[:cells][3] == '3160000.00', table[:rows].last[:cells][3]
    end

    check('second build creates a new group without touching the first') do
      first = session.container
      session.update_settings('mode' => 'grid', 'columns' => 2)
      session.build
      assert first.valid? && session.container != first, 'new container'
      ys = session.container.entities.grep(Sketchup::Group).map { |g| g.bounds.min.y.round(3) }.uniq
      assert ys.size == 2, "grid rows #{ys}"
    end

    check('one Ctrl+Z removes the whole build') do
      container = session.container
      levels = session.levels.map(&:z)
      # Так SketchUp сообщает инструменту о Ctrl+Z, затем сам отменяет операцию.
      session.tool.onCancel(2, m.active_view)
      Sketchup.undo
      assert !container.valid?, 'container removed by single undo'
      assert session.levels.map(&:z) == levels, 'planes kept when the build is undone'
      assert building.valid? && building.entities.grep(Sketchup::Group).size == 3, 'source intact'
    end
  ensure
    session.close if session
    SS::Session.save_settings(saved_settings)
    clean
    m.selection.clear
    old_selection.each { |e| m.selection.add(e) if e.valid? }
  end
  puts "workflow: #{passed} checks passed"
end
