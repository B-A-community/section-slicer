# Copyright 2026 B&A community. Licensed under Apache License 2.0.

module BACommunity
  module SectionSlicer

    # Все строки интерфейса в одном месте. Для перевода достаточно заменить
    # значения хеша; ключи с префиксом ui_ уходят в HtmlDialog.
    STRINGS = {
      # Меню, панель, операции
      menu_slice:        'Сечения по отметкам',
      menu_report:       'Таблица площадей сечений',
      toolbar:           'Section Slicer',
      tip_slice:         'Сечения по отметкам',
      status_slice:      'Горизонтальные сечения группы или компонента',
      tip_report:        'Таблица площадей',
      status_report:     'Открыть таблицу площадей выделенной группы сечений',
      op_build:          'Сечения по отметкам',

      # Отказы и предупреждения
      select_one:        'Выделите одну группу или компонент.',
      select_report:     'Выделите группу сечений, созданную Section Slicer.',
      no_faces:          'В объекте нет видимых граней — резать нечего.',
      not_solid:         'Объект не замкнутое тело: сечения строятся по тем граням, что есть, контуры могут разрываться.',
      no_planes:         'Добавьте хотя бы одну плоскость внутри габарита объекта.',
      skipped:           'Вне габарита объекта, пропущено отметок: {n}.',
      built:             'Построено сечений: {n} за {sec} с.',
      built_gaps:        'С разрывами: {n} — их рёбра оставлены, грани не созданы.',
      built_empty:       'Пустых сечений: {n}.',
      build_failed:      'Построение отменено: {msg}',
      bad_length:        'Не понял значение «{text}».',
      not_found:         'Грань не найдена — сечения удалены или отменены.',
      csv_saved:         'CSV сохранён: {path}',
      csv_title:         'Экспорт таблицы площадей',
      report_opened:     'Таблица загружена из группы «{name}».',

      kind_group:        'группа',
      kind_component:    'компонент',

      # Подписи в модели
      section_name:      'Сечение №{n} · {z}',
      container_name:    'Сечения · {name}',
      label:             "№{n} · {z}\n{area} {unit}",
      plane_label:       '№{n} · {z}',
      plane_out:         '{z} · вне габарита',
      plane_pending:     'Новая · {z}',
      vcb_label:         'Отметка',
      tool_status:       'Клик по точке — отметка плоскости. N — новая плоскость, Delete — удалить, Esc — отмена, Enter — построить.',
      tool_status_idle:  'N — новая плоскость, Delete — удалить активную, Esc/Ctrl+Z — отменить действие, Enter — построить.',

      # Окно
      ui_title:          'Сечения по отметкам',
      ui_planes:         'Плоскости',
      ui_add:            'Добавить',
      ui_add_tip:        'Новая плоскость: клик по точке объекта (клавиша N)',
      ui_undo:           'Отменить',
      ui_undo_tip:       'Отменить последнее действие (Esc / Ctrl+Z)',
      ui_col_n:          '№',
      ui_col_z:          'Отметка',
      ui_col_step:       'Шаг',
      ui_col_count:      'Копий',
      ui_rebind:         'Перепривязать: клик по новой точке',
      ui_remove:         'Удалить плоскость',
      ui_pending_new:    'Кликните точку объекта или введите отметку в Measurements…',
      ui_pending_rebind: 'Кликните новую точку для плоскости…',
      ui_no_planes:      'Плоскостей нет. Нажмите «Добавить» или N и кликните точку объекта.',
      ui_levels:         'Сечений: {n}',
      ui_levels_out:     'вне габарита: {n}',
      ui_layout:         'Раскладка',
      ui_gap:            'Отступ, % ширины',
      ui_mode:           'Расположение',
      ui_mode_row:       'В ряд',
      ui_mode_grid:      'Сеткой',
      ui_columns:        'Столбцов',
      ui_area_unit:      'Площадь в',
      ui_decimal:        'Разделитель',
      ui_results:        'Площади',
      ui_copy:           'Копировать',
      ui_copy_tip:       'В буфер как таблица — вставка в Excel / Google Таблицы по ячейкам',
      ui_csv:            'Экспорт CSV',
      ui_copied:         'Таблица скопирована',
      ui_no_results:     'Таблица появится после построения.',
      ui_build:          'Построить сечения',
      ui_cancel:         'Закрыть',
      ui_tool_off:       'Инструмент плоскостей выключен — «Добавить» включит его снова.',

      # Таблица
      col_section:       '№ сечения',
      col_z:             'Отметка',
      col_contour:       '№ контура',
      col_area:          'Площадь, {unit}',
      col_perimeter:     'Периметр, {unit}',
      col_status:        'Статус',
      st_ok:             'OK',
      st_gap:            'разрыв',
      st_gaps:           'есть разрывы',
      st_empty:          'пусто',
      row_total:         'Итого',
      row_grand:         'Всего',

      unit_m2: 'м²', unit_cm2: 'см²', unit_mm2: 'мм²', unit_ft2: 'ft²',
      unit_m:  'м',  unit_cm:  'см',  unit_mm:  'мм',  unit_ft:  'ft', unit_in: 'in', unit_yd: 'yd'
    }.freeze

    def self.t(key, vars = {})
      text = STRINGS.fetch(key) { key.to_s }
      vars.each { |name, value| text = text.gsub("{#{name}}", value.to_s) }
      text
    end

    def self.ui_strings
      STRINGS.select { |key, _| key.to_s.start_with?('ui_') }
             .map { |key, value| [key.to_s.sub('ui_', ''), value] }.to_h
    end

  end # module SectionSlicer
end # module BACommunity
