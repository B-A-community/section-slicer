# Copyright 2026 B&A community. Licensed under Apache License 2.0.

module BACommunity
  module SectionSlicer

    # Раскладка: общая группа «Сечения · <имя>», в ней группа на каждое
    # сечение, опущенная на Z = 0 правее габарита исходного объекта, и
    # подписи. Каждая ячейка раскладки повторяет план габарита объекта,
    # поэтому сечения разных отметок совпадают друг с другом при наложении.
    module Layout

      module_function

      # object_box — [xmin, ymin, zmin, xmax, ymax, zmax] в мировых координатах.
      # Возвращает смещение [dx, dy] для каждого номера ячейки 0…n−1.
      def offsets(object_box, count, settings)
        xmin, ymin, _, xmax, ymax, = object_box
        width = [xmax - xmin, 1.0].max
        depth = [ymax - ymin, 1.0].max
        gap = width * [settings['gap'].to_f, 0.0].max / 100.0
        columns = settings['mode'] == 'grid' ? [settings['columns'].to_i, 1].max : count
        # От модели отступаем не меньше 10% её ширины, даже при нулевом отступе.
        x0 = xmax + [gap, width * 0.1].max
        (0...count).map do |i|
          col = i % columns
          row = i / columns
          [x0 + col * (width + gap) - xmin, -row * (depth + gap * 1.5)]
        end
      end

      # Строит всё внутри одной операции, открытой вызывающим.
      # sections — [[Level, Slicer::Section], ...] по возрастанию отметки.
      def build(model, instance, object_box, sections, settings)
        entities = model.active_entities
        container = entities.add_group
        # Расчёт в мировых координатах. В открытом контексте SketchUp 2020+
        # тоже работает в мировых, поэтому трансформация остаётся единичной.
        name = source_name(instance)
        container.name = SectionSlicer.t(:container_name, name: name)

        sep = Units.resolve_decimal(settings['decimal'])
        area_unit = settings['area_unit']
        xmin, ymin, = object_box
        width = object_box[3] - xmin
        records = []
        offsets(object_box, sections.size, settings).each_with_index do |(dx, dy), i|
          level, section = sections[i]
          z_label = Units.format_elevation(level.z, sep, group: true, model: model)
          record = { 'n' => level.number, 'z' => level.z, 'pid' => nil, 'contours' => [] }
          unless section.empty?
            group = container.entities.add_group
            group.name = SectionSlicer.t(:section_name, n: level.number, z: z_label)
            result = Slicer.fill(group.entities, section)
            group.transformation = Geom::Transformation.translation([dx, dy, 0])
            record['pid'] = group.persistent_id
            result[:faces].sort_by { |face| -face.area }.each do |face|
              record['contours'] << {
                'pid' => face.persistent_id, 'area' => face.area.to_f,
                'perimeter' => face.edges.sum(&:length).to_f, 'closed' => true
              }
            end
            result[:chains].each do |length, edges|
              record['contours'] << {
                'pid' => edges.first && edges.first.persistent_id, 'area' => nil,
                'perimeter' => length, 'closed' => false
              }
            end
          end
          record['status'] = if record['contours'].empty? then 'empty'
                             elsif record['contours'].any? { |c| !c['closed'] } then 'gaps'
                             else 'ok'
                             end
          area = record['contours'].sum { |c| c['area'] || 0.0 }
          label = SectionSlicer.t(:label, n: level.number, z: z_label,
                                          area: Units.format_number(Units.area(area, area_unit), 2, sep),
                                          unit: Units.area_label(area_unit))
          anchor = Geom::Point3d.new(xmin + dx + width / 2.0, ymin + dy - width * 0.04, 0)
          container.entities.add_text(label, anchor)
          records << record
        end

        report = {
          'version' => 1, 'source' => name, 'created' => Time.now.strftime('%Y-%m-%d %H:%M'),
          'length_unit' => Units.length_unit(model), 'sections' => records
        }
        AreaReport.store(container, report)
        [container, report]
      end

      def source_name(instance)
        name = instance.name.to_s
        name = instance.definition.name.to_s if name.empty?
        name
      end

    end # module Layout

  end # module SectionSlicer
end # module BACommunity
