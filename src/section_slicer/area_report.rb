# Copyright 2026 B&A community. Licensed under Apache License 2.0.

require 'json'

module BACommunity
  module SectionSlicer

    # Таблица площадей: строка на каждый контур, итог по сечению, общий итог.
    # Сырые данные (дюймы) хранятся в атрибутах общей группы; таблица,
    # TSV и CSV строятся из них под выбранные единицы и разделитель.
    module AreaReport

      DICT = 'SectionSlicer'.freeze
      KEY  = 'report'.freeze

      module_function

      def store(group, report)
        group.set_attribute(DICT, KEY, JSON.generate(report))
      end

      def load(group)
        return nil unless group && group.valid?
        json = group.get_attribute(DICT, KEY)
        json ? JSON.parse(json) : nil
      rescue JSON::ParserError
        nil
      end

      def stored?(entity)
        entity.is_a?(Sketchup::Group) && !entity.get_attribute(DICT, KEY).nil?
      end

      # → { header: [...], rows: [{ cells:, kind: 'face'|'gap'|'total'|'grand', pid: }], totals: }
      def table(report, settings, model = Sketchup.active_model)
        sep = Units.resolve_decimal(settings['decimal'])
        unit = settings['area_unit']
        header = [
          SectionSlicer.t(:col_section), SectionSlicer.t(:col_z), SectionSlicer.t(:col_contour),
          SectionSlicer.t(:col_area, unit: Units.area_label(unit)),
          SectionSlicer.t(:col_perimeter, unit: Units.perimeter_label(unit)),
          SectionSlicer.t(:col_status)
        ]
        num = ->(value) { value.nil? ? '' : Units.format_number(value, 2, sep) }
        rows = []
        grand_area = 0.0
        grand_perimeter = 0.0
        report['sections'].each do |section|
          n = section['n']
          z = Units.format_elevation(section['z'], sep, model: model)
          z_plain = Units.format_plain(section['z'], sep, model: model)
          section_area = 0.0
          section_perimeter = 0.0
          section['contours'].each_with_index do |contour, i|
            area = contour['area'] && Units.area(contour['area'], unit)
            perimeter = Units.perimeter(contour['perimeter'], unit)
            section_area += area.to_f
            section_perimeter += perimeter
            rows << {
              cells: [n, z, "#{n}.#{i + 1}", num.call(area), num.call(perimeter),
                      SectionSlicer.t(contour['closed'] ? :st_ok : :st_gap)],
              plain_z: z_plain, kind: contour['closed'] ? 'face' : 'gap', pid: contour['pid']
            }
          end
          status = { 'ok' => :st_ok, 'gaps' => :st_gaps, 'empty' => :st_empty }.fetch(section['status'], :st_ok)
          rows << {
            cells: [n, z, SectionSlicer.t(:row_total), num.call(section_area),
                    num.call(section_perimeter), SectionSlicer.t(status)],
            plain_z: z_plain, kind: 'total', pid: section['pid']
          }
          grand_area += section_area
          grand_perimeter += section_perimeter
        end
        rows << {
          cells: [SectionSlicer.t(:row_grand), '', '', num.call(grand_area), num.call(grand_perimeter), ''],
          plain_z: '', kind: 'grand', pid: nil
        }
        { header: header, rows: rows, total_area: grand_area }
      end

      # Строки для буфера/файла: отметка — простым числом, номер контура
      # формулой ="3.2", иначе Excel в русской локали превратит его в дату.
      def export_rows(table)
        body = table[:rows].map do |row|
          cells = row[:cells].dup
          cells[1] = row[:plain_z]
          cells[2] = %(="#{cells[2]}") if row[:kind] == 'face' || row[:kind] == 'gap'
          cells.map(&:to_s)
        end
        [table[:header]] + body
      end

      def tsv(table)
        export_rows(table).map { |cells| cells.map { |c| c.tr("\t\r\n", '   ') }.join("\t") }.join("\r\n") + "\r\n"
      end

      # HTML-вариант для буфера: Excel и Google Таблицы раскладывают его по
      # ячейкам, номер контура помечен текстовым форматом.
      def html(table)
        escape = ->(s) { s.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;') }
        rows = export_rows(table).each_with_index.map do |cells, r|
          tag = r.zero? ? 'th' : 'td'
          bold = r > 0 && %w[total grand].include?(table[:rows][r - 1][:kind])
          inner = cells.map do |c|
            m = /\A="(.*)"\z/.match(c)
            style = m ? %( style="mso-number-format:'\\@'") : ''
            "<#{tag}#{style}>#{escape.call(m ? m[1] : c)}</#{tag}>"
          end.join
          bold ? %(<tr style="font-weight:bold">#{inner}</tr>) : "<tr>#{inner}</tr>"
        end
        "<table>#{rows.join}</table>"
      end

      # CSV для Excel: при десятичной запятой разделитель полей — «;».
      def csv(table, settings)
        delimiter = Units.resolve_decimal(settings['decimal']) == ',' ? ';' : ','
        lines = export_rows(table).map do |cells|
          cells.map { |c| c.include?(delimiter) || c.include?('"') ? %("#{c.gsub('"', '""')}") : c }.join(delimiter)
        end
        "﻿" + lines.join("\r\n") + "\r\n"
      end

    end # module AreaReport

  end # module SectionSlicer
end # module BACommunity
