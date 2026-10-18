# Copyright 2026 B&A community. Licensed under Apache License 2.0.

module BACommunity
  module SectionSlicer

    # SketchUp хранит длины в дюймах. Здесь — перевод в единицы модели,
    # единицы площади и форматирование чисел с выбранным разделителем.
    module Units

      # LengthUnit из UnitsOptions → [ключ строки, дюймов в единице, знаков в отметке]
      LENGTH = {
        0 => [:unit_in, 1.0,          2],
        1 => [:unit_ft, 12.0,         3],
        2 => [:unit_mm, 1.0 / 25.4,   0],
        3 => [:unit_cm, 1.0 / 2.54,   1],
        4 => [:unit_m,  1.0 / 0.0254, 3],
        5 => [:unit_yd, 36.0,         3]
      }.freeze

      # Единица площади → [множитель от кв. дюймов, строка, единица периметра, множитель от дюймов]
      AREA = {
        'm2'  => [0.0254**2,    :unit_m2,  :unit_m,  0.0254],
        'cm2' => [2.54**2,      :unit_cm2, :unit_cm, 2.54],
        'mm2' => [25.4**2,      :unit_mm2, :unit_mm, 25.4],
        'ft2' => [1.0 / 144.0,  :unit_ft2, :unit_ft, 1.0 / 12.0]
      }.freeze

      module_function

      def length_unit(model = Sketchup.active_model)
        code = model && model.options['UnitsOptions']['LengthUnit']
        LENGTH.key?(code) ? code : 2
      end

      def length_info(model = Sketchup.active_model)
        LENGTH[length_unit(model)]
      end

      def to_model(inches, model = Sketchup.active_model)
        inches.to_f / length_info(model)[1]
      end

      def unit_name(model = Sketchup.active_model)
        SectionSlicer.t(length_info(model)[0])
      end

      def system_decimal
        if defined?(Sketchup::RegionalSettings) && Sketchup::RegionalSettings.respond_to?(:decimal_separator)
          Sketchup::RegionalSettings.decimal_separator
        else
          Sketchup.get_locale.to_s.start_with?('en') ? '.' : ','
        end
      rescue StandardError
        ','
      end

      def resolve_decimal(setting)
        setting == ',' || setting == '.' ? setting : system_decimal
      end

      # 3000.0, 0, ',' , group: true → "3 000"
      def format_number(value, decimals, sep, group: false)
        rounded = value.to_f.round(decimals)
        text = format("%.#{decimals}f", rounded.abs)
        int, frac = text.split('.')
        int = int.reverse.scan(/\d{1,3}/).join(' ').reverse if group && int.length > 3
        body = frac ? "#{int}#{sep}#{frac}" : int
        rounded < 0 ? "-#{body}" : body
      end

      # Архитектурная отметка: всегда со знаком, ноль — «±0».
      def format_elevation(inches, sep, group: false, model: Sketchup.active_model)
        _, _, decimals = length_info(model)
        value = to_model(inches, model).round(decimals)
        body = format_number(value.abs, decimals, sep, group: group)
        return "±#{body}" if value.zero?
        value > 0 ? "+#{body}" : "-#{body}"
      end

      # Число для таблицы: без группировки разрядов, «+» для положительных
      # отметок не нужен — Excel и так поймёт число.
      def format_plain(inches, sep, model: Sketchup.active_model)
        _, _, decimals = length_info(model)
        format_number(to_model(inches, model), decimals, sep)
      end

      def area(square_inches, unit)
        square_inches.to_f * AREA.fetch(unit, AREA['m2'])[0]
      end

      def perimeter(inches, unit)
        inches.to_f * AREA.fetch(unit, AREA['m2'])[3]
      end

      def area_label(unit)
        SectionSlicer.t(AREA.fetch(unit, AREA['m2'])[1])
      end

      def perimeter_label(unit)
        SectionSlicer.t(AREA.fetch(unit, AREA['m2'])[2])
      end

      # Ввод длины пользователем: «3000», «3 м», «1,5». Возвращает дюймы или nil.
      def parse_length(text)
        clean = text.to_s.strip.delete(' ').delete(" ")
        return nil if clean.empty?
        [clean, clean.tr(',', '.'), clean.tr('.', ',')].uniq.each do |variant|
          begin
            return variant.to_l.to_f
          rescue ArgumentError
            next
          end
        end
        nil
      end

    end # module Units

  end # module SectionSlicer
end # module BACommunity
