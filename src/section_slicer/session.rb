# Copyright 2026 B&A community. Licensed under Apache License 2.0.

require 'json'

module BACommunity
  module SectionSlicer

    # Одна сессия работы: выбранный объект, набор плоскостей, окно
    # HtmlDialog и инструмент. Окно и инструмент общаются только через неё.
    class Session

      PREF = 'BACommunity_SectionSlicer'.freeze
      DEFAULTS = {
        'gap' => 20.0, 'mode' => 'row', 'columns' => 4, 'area_unit' => 'm2', 'decimal' => 'auto'
      }.freeze

      class << self
        attr_reader :current

        # Точка входа из меню/панели.
        def start(model = Sketchup.active_model)
          selection = model.selection.to_a
          instance = selection.first
          unless selection.size == 1 && instance_like?(instance)
            UI.messagebox(SectionSlicer.t(:select_one))
            return nil
          end
          return open_report(instance) if AreaReport.stored?(instance)
          launch(model, instance)
        end

        def launch(model, instance)
          @current.close if @current
          @current = new(model, instance)
          @current.show
          @current
        end

        # Повторное открытие таблицы из атрибутов группы сечений.
        def open_report(group = nil, model = Sketchup.active_model)
          group ||= model.selection.first
          report = AreaReport.stored?(group) && AreaReport.load(group)
          unless report
            UI.messagebox(SectionSlicer.t(:select_report))
            return nil
          end
          @current.close if @current
          @current = new(model, nil)
          @current.load_report(group, report)
          @current.show
          @current
        end

        def instance_like?(entity)
          entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
        end

        def forget(session)
          @current = nil if @current.equal?(session)
        end

        def settings
          DEFAULTS.map do |key, value|
            stored = Sketchup.read_default(PREF, key, value)
            [key, value.is_a?(Numeric) ? stored.to_f : stored.to_s]
          end.to_h
        end

        def save_settings(settings)
          settings.each { |key, value| Sketchup.write_default(PREF, key, value) }
        end
      end

      attr_reader :model, :instance, :planes, :pending, :object_box, :settings,
                  :report, :container, :tool, :dialog, :notices

      def initialize(model, instance)
        @model = model
        @instance = instance
        @settings = self.class.settings
        @notices = []
        @report = nil
        @container = nil
        @tool_active = false
        @pending = nil
        @tool = PlaneTool.new(self)
        return unless instance

        refresh_geometry
        @planes = PlaneSet.new(@object_box[2], @object_box[5])
        @pending = :new
        @solid = Slicer.solid?(instance.definition.entities)
        @notices << [:warn, SectionSlicer.t(:not_solid)] unless @solid
        @notices << [:bad, SectionSlicer.t(:no_faces)] if @faces.empty?
      end

      # --- Геометрия объекта --------------------------------------------

      # С SketchUp 2020 трансформации в открытом контексте уже мировые.
      def world_transformation
        @instance.transformation
      end

      def refresh_geometry
        @faces = Slicer.collect(@instance.definition.entities, world_transformation)
        @object_box = Slicer.bounds(@faces) || begin
          box = @instance.bounds
          [box.min.x, box.min.y, box.min.z, box.max.x, box.max.y, box.max.z].map(&:to_f)
        end
        @planes.bounds = [@object_box[2], @object_box[5]] if @planes
      end

      # Прямоугольник плоскости: габарит плюс 10% с каждой стороны.
      def frame
        return nil unless @object_box
        xmin, ymin, _, xmax, ymax, = @object_box
        size = [xmax - xmin, ymax - ymin].max
        mx = [(xmax - xmin) * PlaneTool::MARGIN, size * 0.02].max
        my = [(ymax - ymin) * PlaneTool::MARGIN, size * 0.02].max
        [xmin - mx, ymin - my, xmax + mx, ymax + my]
      end

      def levels
        @planes ? @planes.levels : []
      end

      # --- Действия инструмента и окна ----------------------------------

      def activate_tool
        return unless @instance && @instance.valid?
        @model.select_tool(@tool) unless @tool_active
      end

      def tool_state_changed(active)
        @tool_active = active
        push_state
      end

      def begin_new
        return unless @planes
        @pending = :new
        activate_tool
        changed
      end

      def rebind(id)
        return unless @planes && @planes.find(id)
        @planes.select(id)
        @pending = [:rebind, id.to_i]
        activate_tool
        changed
      end

      def click_elevation(z)
        return unless @planes && @pending
        if @pending.is_a?(Array)
          @planes.set_z(@pending[1], z)
        else
          @planes.add(z)
        end
        @pending = nil
        changed
      end

      # VCB: «3000» — абсолютная отметка, «+500» / «-500» — от последней плоскости.
      def typed_elevation(text)
        return unless @planes
        clean = text.to_s.strip
        relative = clean.start_with?('+', '-') && @planes.last
        value = Units.parse_length(relative ? clean[1..-1] : clean)
        unless value
          UI.beep
          notify(:bad, SectionSlicer.t(:bad_length, text: clean))
          return
        end
        value = @planes.last.z + (clean.start_with?('-') ? -value : value) if relative
        if @pending.is_a?(Array)
          @planes.set_z(@pending[1], value)
        else
          @planes.add(value)
        end
        @pending = nil
        changed
      end

      def remove(id)
        return unless @planes
        @pending = nil if @pending.is_a?(Array) && @pending[1] == id.to_i
        @planes.remove(id)
        changed
      end

      def remove_active
        remove(@planes.active_id) if @planes && @planes.active_id
      end

      def select(id)
        return unless @planes
        @planes.select(id)
        changed
      end

      def set_z(id, text)
        value = Units.parse_length(text)
        return notify(:bad, SectionSlicer.t(:bad_length, text: text)) unless value
        @planes.set_z(id, value)
        changed
      end

      def set_array(id, step_text, count)
        step = Units.parse_length(step_text.to_s.empty? ? '0' : step_text)
        return notify(:bad, SectionSlicer.t(:bad_length, text: step_text)) unless step
        @planes.set_array(id, step, count.to_i)
        changed
      end

      def escape
        if @pending
          @pending = nil
          changed
        else
          undo
        end
      end

      def undo
        return unless @planes
        @pending = nil
        @planes.undo
        changed
      end

      # Ctrl+Z при активном инструменте: SketchUp уже отменяет последнюю
      # операцию модели. Если ею было построение — отменяется только оно,
      # плоскости остаются; иначе откатывается действие с плоскостями.
      def model_undo
        if @built_last
          @built_last = false
          @pending = nil
          UI.start_timer(0, false) { forget_undone_build }
        else
          undo
        end
      end

      def forget_undone_build
        return if @container.nil? || @container.valid?
        @container = nil
        @report = nil
        @notices = []
        changed
      end

      def update_settings(values)
        values.each do |key, value|
          next unless DEFAULTS.key?(key)
          @settings[key] = DEFAULTS[key].is_a?(Numeric) ? value.to_f : value.to_s
        end
        self.class.save_settings(@settings)
        push_state
      end

      # --- Построение ---------------------------------------------------

      def build
        return unless @instance
        unless @instance.valid?
          notify(:bad, SectionSlicer.t(:select_one))
          return
        end
        refresh_geometry
        all = levels
        inside = all.select(&:inside)
        skipped = all.size - inside.size
        @notices = []
        @notices << [:warn, SectionSlicer.t(:skipped, n: skipped)] if skipped > 0
        if inside.empty?
          notify(:bad, SectionSlicer.t(:no_planes))
          return
        end

        started = Time.now
        @model.start_operation(SectionSlicer.t(:op_build), true)
        begin
          sections = inside.map { |level| [level, Slicer.section(@faces, level.z, @object_box[5])] }
          @container, @report = Layout.build(@model, @instance, @object_box, sections, @settings)
          @model.commit_operation
          @built_last = true
        rescue StandardError => e
          @model.abort_operation
          puts "Section Slicer: #{e.class}: #{e.message}\n#{e.backtrace.first(8).join("\n")}"
          notify(:bad, SectionSlicer.t(:build_failed, msg: e.message))
          return
        end

        @notices.unshift([:ok, SectionSlicer.t(:built, n: inside.size, sec: Units.format_number(Time.now - started, 1, Units.resolve_decimal(@settings['decimal'])))])
        gaps = @report['sections'].count { |s| s['status'] == 'gaps' }
        empty = @report['sections'].count { |s| s['status'] == 'empty' }
        @notices << [:warn, SectionSlicer.t(:built_gaps, n: gaps)] if gaps > 0
        @notices << [:warn, SectionSlicer.t(:built_empty, n: empty)] if empty > 0
        @model.active_view.invalidate
        push_state
        @report
      end

      def load_report(group, report)
        @container = group
        @report = report
        @notices = [[:ok, SectionSlicer.t(:report_opened, name: group.name)]]
      end

      def table
        @report && AreaReport.table(@report, @settings, @model)
      end

      # Копирование из Ruby; при неудаче окно пробует свой способ.
      def copy_table
        current = table or return
        ok = Clipboard.copy(AreaReport.tsv(current), AreaReport.html(current))
        @dialog.execute_script("SS.copied(#{ok})") if @dialog
        ok
      end

      def export_csv
        current = table or return
        name = "#{(@report['source'] || 'sections').gsub(/[\\\/:*?"<>|]/, '_')}.csv"
        path = UI.savepanel(SectionSlicer.t(:csv_title), nil, name)
        return unless path
        path += '.csv' unless path.downcase.end_with?('.csv')
        File.write(path, AreaReport.csv(current, @settings), mode: 'wb', encoding: 'UTF-8')
        notify(:ok, SectionSlicer.t(:csv_saved, path: path))
      end

      # Клик по строке таблицы: открыть группу сечения и выбрать грань.
      def select_entity(pid)
        entity = pid && @model.find_entity_by_persistent_id(pid.to_i)
        unless entity && entity.valid?
          notify(:warn, SectionSlicer.t(:not_found))
          return false
        end
        if entity.is_a?(Sketchup::Group)
          path = instance_path(entity)
          @model.active_path = path[0..-2].empty? ? nil : path[0..-2]
        else
          owner = entity.parent.respond_to?(:instances) && entity.parent.instances.first
          return false unless owner
          @model.active_path = instance_path(owner)
        end
        @model.selection.clear
        @model.selection.add(entity)
        @model.active_view.invalidate
        true
      rescue ArgumentError => e
        notify(:warn, e.message)
        false
      end

      def instance_path(instance)
        path = [instance]
        parent = instance.parent
        while parent.is_a?(Sketchup::ComponentDefinition)
          owner = parent.instances.first or break
          path.unshift(owner)
          parent = owner.parent
        end
        path
      end

      # --- Окно ---------------------------------------------------------

      def show
        @dialog = UI::HtmlDialog.new(
          dialog_title: SectionSlicer.t(:ui_title), preferences_key: 'BACommunity_SectionSlicer_Dialog',
          scrollable: false, resizable: true, width: 620, height: 780, min_width: 480, min_height: 520,
          style: UI::HtmlDialog::STYLE_DIALOG
        )
        @dialog.set_file(File.join(HERE, 'ui', 'dialog.html'))
        register_callbacks
        @dialog.set_on_closed { closed }
        @dialog.show
        activate_tool
      end

      # Окно, закрытое в том же тике, что и открыто, всё равно появится —
      # поэтому закрытая сессия закрывает его ещё раз по колбэку ready.
      def close
        @closed = true
        @dialog.close if @dialog
        closed
      end

      def closed
        @closed = true
        @model.select_tool(nil) if @tool_active
        @tool_active = false
        self.class.forget(self)
      end

      def changed
        @model.active_view.invalidate if @model.valid?
        @tool.update_ui if @tool_active
        push_state
      end

      def notify(kind, text)
        @notices = [[kind, text]]
        push_state
        nil
      end

      def state
        sep = Units.resolve_decimal(@settings['decimal'])
        all = levels
        current = table
        {
          strings: SectionSlicer.ui_strings,
          object: object_state,
          unit: Units.unit_name(@model),
          planes: plane_rows(all, sep),
          levels: { inside: all.count(&:inside), out: all.count { |l| !l.inside } },
          pending: @pending.is_a?(Array) ? 'rebind' : @pending && 'new',
          tool_active: @tool_active,
          can_undo: @planes ? @planes.can_undo? : false,
          settings: @settings.merge('decimal_resolved' => sep),
          notices: @notices.map { |kind, text| { kind: kind, text: text } },
          table: current && {
            header: current[:header],
            rows: current[:rows].map { |r| { cells: r[:cells], kind: r[:kind], pid: r[:pid] } },
            tsv: AreaReport.tsv(current)
          }
        }
      end

      def push_state
        return unless @dialog && @dialog.visible?
        @dialog.execute_script("SS.render(#{JSON.generate(state)})")
      end

      private

      def object_state
        if @instance
          { name: Layout.source_name(@instance), solid: @solid, mode: 'slice',
            kind: SectionSlicer.t(@instance.is_a?(Sketchup::Group) ? :kind_group : :kind_component) }
        else
          { name: @container && @container.valid? ? @container.name : (@report && @report['source']).to_s,
            mode: 'report' }
        end
      end

      def plane_rows(all, sep)
        return [] unless @planes
        numbers = {}
        all.each { |level| numbers[level.plane_id] ||= level.number if level.copy.zero? }
        @planes.planes.sort_by(&:z).map do |plane|
          {
            id: plane.id, number: numbers[plane.id],
            z: Units.format_plain(plane.z, sep, model: @model),
            z_label: Units.format_elevation(plane.z, sep, group: true, model: @model),
            step: plane.step.zero? ? '' : Units.format_plain(plane.step, sep, model: @model),
            count: plane.count,
            inside: @planes.inside?(plane.z),
            active: plane.id == @planes.active_id,
            rebinding: @pending.is_a?(Array) && @pending[1] == plane.id
          }
        end
      end

      def register_callbacks
        d = @dialog
        d.add_action_callback('ready') { |_| @closed ? d.close : push_state }
        d.add_action_callback('add') { |_| begin_new }
        d.add_action_callback('rebind') { |_, id| rebind(id) }
        d.add_action_callback('remove') { |_, id| remove(id) }
        d.add_action_callback('select') { |_, id| select(id) }
        d.add_action_callback('set_z') { |_, id, text| set_z(id, text) }
        d.add_action_callback('set_array') { |_, id, step, count| set_array(id, step, count) }
        d.add_action_callback('undo') { |_| undo }
        d.add_action_callback('escape') { |_| escape }
        d.add_action_callback('settings') { |_, json| update_settings(JSON.parse(json)) }
        d.add_action_callback('build') { |_| build }
        d.add_action_callback('select_entity') { |_, pid| select_entity(pid) }
        d.add_action_callback('copy') { |_| copy_table }
        d.add_action_callback('export_csv') { |_| export_csv }
        d.add_action_callback('cancel') { |_| close }
      end

    end # class Session

  end # module SectionSlicer
end # module BACommunity
