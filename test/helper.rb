# Общая подготовка тестов: исходники грузятся заново из src/, без
# установки расширения. Все проверки исполняются внутри SketchUp 2024.
raise 'Tests require SketchUp 2024' unless Sketchup.version.to_i == 24

module BACommunity
  module SectionSlicer
    HERE = File.expand_path('../src/section_slicer', __dir__) unless defined?(HERE)
    EXTENSION_NAME = 'Section Slicer' unless defined?(EXTENSION_NAME)
  end
end

SS_SRC = File.expand_path('../src/section_slicer', __dir__) unless defined?(SS_SRC)
%w[lang strings units plane_set slicer area_report clipboard layout plane_tool session].each do |name|
  load File.join(SS_SRC, "#{name}.rb")
end

module SSTest
  SS = BACommunity::SectionSlicer
  MM = 1.0 / 25.4
  @passed = 0

  class << self
    attr_reader :passed

    def check(name)
      yield
      @passed += 1
      puts "PASS #{name}"
    rescue StandardError => e
      puts "FAIL #{name}: #{e.message}"
      puts e.backtrace.first(4).join("\n")
      raise
    end

    def assert(cond, message)
      raise message unless cond
    end

    def near(a, b, tol, message)
      raise "#{message}: #{a} vs #{b}" unless (a - b).abs <= tol
    end

    def model
      Sketchup.active_model
    end

    # Коробка в мм внутри новой группы; возвращает группу.
    def box(entities, x, y, z, w, d, h)
      group = entities.add_group
      pts = [[x, y, z], [x + w, y, z], [x + w, y + d, z], [x, y + d, z]].map { |p| Geom::Point3d.new(*p.map { |v| v * MM }) }
      face = group.entities.add_face(pts)
      face.reverse! if face.normal.z < 0
      face.pushpull(h * MM)
      group
    end

    def clean(prefix = 'SS_TEST')
      model.active_path = nil if model.active_path
      model.entities.to_a.each do |e|
        next unless e.valid? && (e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance))
        e.erase! if e.name.start_with?(prefix) || e.name.start_with?('Сечения · SS_TEST')
      end
    end

    def m2(square_inches)
      square_inches * 0.0254**2
    end
  end
end
