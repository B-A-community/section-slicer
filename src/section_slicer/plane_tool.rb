# Copyright 2026 B&A community. Licensed under Apache License 2.0.

module BACommunity
  module SectionSlicer

    # Инструмент привязки секущих плоскостей. Плоскости — только временная
    # отрисовка через view.draw; модель инструмент не меняет. Данные и
    # действия живут в Session, здесь — мышь, клавиатура и рисование.
    class PlaneTool

      MARGIN = 0.10 # запас плоскости вокруг габарита с каждой стороны

      COLORS = {
        active:  [Sketchup::Color.new(221, 138, 32, 70),  Sketchup::Color.new(221, 138, 32)],
        normal:  [Sketchup::Color.new(43, 108, 176, 34),  Sketchup::Color.new(43, 108, 176, 200)],
        copy:    [Sketchup::Color.new(43, 108, 176, 18),  Sketchup::Color.new(43, 108, 176, 130)],
        out:     [Sketchup::Color.new(136, 136, 136, 22), Sketchup::Color.new(136, 136, 136, 170)],
        pending: [Sketchup::Color.new(221, 138, 32, 45),  Sketchup::Color.new(221, 138, 32)]
      }.freeze

      KEY_N      = [78, 110].freeze
      KEY_RETURN = [13, 3].freeze

      attr_reader :hover_z

      def initialize(session)
        @session = session
        @ip = Sketchup::InputPoint.new
        @hover_z = nil
      end

      def activate
        @ip = Sketchup::InputPoint.new
        @hover_z = nil
        update_ui
        @session.tool_state_changed(true)
        Sketchup.active_model.active_view.invalidate
      end

      def deactivate(view)
        view.invalidate
        @session.tool_state_changed(false)
      end

      def resume(view)
        update_ui
        view.invalidate
      end

      def suspend(view)
        view.invalidate
      end

      def update_ui
        Sketchup.status_text = SectionSlicer.t(@session.pending ? :tool_status : :tool_status_idle)
        Sketchup.vcb_label = SectionSlicer.t(:vcb_label)
        Sketchup.vcb_value = @hover_z ? Units.format_plain(@hover_z, Units.resolve_decimal(nil)) : ''
      end

      def enableVCB?
        true
      end

      def onMouseMove(_flags, x, y, view)
        @ip.pick(view, x, y)
        if @ip.valid?
          @hover_z = @ip.position.z.to_f
          view.tooltip = @ip.tooltip
          Sketchup.vcb_value = Units.format_plain(@hover_z, Units.resolve_decimal(nil)) if @session.pending
        else
          @hover_z = nil
        end
        view.invalidate
      end

      def onLButtonDown(_flags, x, y, view)
        @ip.pick(view, x, y)
        return unless @ip.valid? && @session.pending
        @hover_z = @ip.position.z.to_f
        @session.click_elevation(@hover_z)
        update_ui
        view.invalidate
      end

      def onUserText(text, view)
        @session.typed_elevation(text)
        update_ui
        view.invalidate
      end

      def onReturn(_view)
        @session.build
      end

      def onKeyDown(key, _repeat, flags, view)
        ctrl = (flags & COPY_MODIFIER_MASK) != 0
        backspace_mac = key == 8 && Sketchup.platform == :platform_osx
        if KEY_N.include?(key) && !ctrl
          @session.begin_new
        elsif key == VK_DELETE || backspace_mac
          @session.remove_active
        else
          return false
        end
        update_ui
        view.invalidate
        true
      end

      # Esc: сначала отменяет ожидание клика, затем — последнее действие.
      # reason 2 — Ctrl+Z / Edit → Undo SketchUp при активном инструменте.
      def onCancel(reason, view)
        reason == 2 ? @session.model_undo : @session.escape
        update_ui
        view.invalidate
      end

      def getExtents
        box = Geom::BoundingBox.new
        frame = @session.frame
        return box unless frame
        xmin, ymin, xmax, ymax = frame
        zs = @session.levels.map(&:z) + [@session.object_box[2], @session.object_box[5]]
        zs << @hover_z if @hover_z
        [zs.min, zs.max].each do |z|
          box.add(Geom::Point3d.new(xmin, ymin, z), Geom::Point3d.new(xmax, ymax, z))
        end
        box
      end

      def draw(view)
        frame = @session.frame
        return unless frame
        sep = Units.resolve_decimal(nil)
        active_id = @session.planes.active_id
        rebinding = @session.pending.is_a?(Array) ? @session.pending[1] : nil

        @session.levels.each do |level|
          next if level.plane_id == rebinding && level.copy.zero? && @hover_z
          kind = if !level.inside then :out
                 elsif level.plane_id == active_id then level.copy.zero? ? :active : :copy
                 else level.copy.zero? ? :normal : :copy
                 end
          z_text = Units.format_elevation(level.z, sep, group: true)
          text = level.inside ? SectionSlicer.t(:plane_label, n: level.number, z: z_text) : SectionSlicer.t(:plane_out, z: z_text)
          draw_plane(view, frame, level.z, COLORS[kind], text, kind == :active ? 2 : 1)
        end

        if @session.pending && @hover_z
          z_text = Units.format_elevation(@hover_z, sep, group: true)
          draw_plane(view, frame, @hover_z, COLORS[:pending], SectionSlicer.t(:plane_pending, z: z_text), 2)
        end
        @ip.draw(view) if @ip.valid? && @ip.display?
      end

      private

      def draw_plane(view, frame, z, colors, text, width)
        xmin, ymin, xmax, ymax = frame
        pts = [[xmin, ymin], [xmax, ymin], [xmax, ymax], [xmin, ymax]].map do |x, y|
          Geom::Point3d.new(x, y, z)
        end
        view.drawing_color = colors[0]
        view.draw(GL_QUADS, pts)
        view.line_width = width
        view.line_stipple = ''
        view.drawing_color = colors[1]
        view.draw(GL_LINE_LOOP, pts)
        anchor = view.screen_coords(pts[1])
        view.draw_text(Geom::Point3d.new(anchor.x + 6, anchor.y - 18, 0), text,
                       size: 11, bold: width > 1, color: colors[1])
      end

    end # class PlaneTool

  end # module SectionSlicer
end # module BACommunity
