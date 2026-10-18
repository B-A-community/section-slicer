# Copyright 2026 B&A community. Licensed under Apache License 2.0.

module BACommunity
  module SectionSlicer

    # Модель данных секущих плоскостей: исходные отметки, массивы копий,
    # слияние совпадающих отметок, сортировка и нумерация, история отмены.
    # Все отметки — мировые Z в дюймах.
    class PlaneSet

      MERGE_TOL   = 0.1 / 25.4 # 0,1 мм
      MAX_COPIES  = 500
      MAX_HISTORY = 200

      Plane = Struct.new(:id, :z, :step, :count)

      # Итоговая отметка после раскрытия копий. number — порядковый номер
      # сечения (только для отметок внутри габарита), copy — 0 для исходной.
      Level = Struct.new(:z, :number, :plane_id, :copy, :inside)

      attr_reader :planes, :zmin, :zmax
      attr_accessor :active_id

      def initialize(zmin, zmax)
        @zmin = zmin.to_f
        @zmax = zmax.to_f
        @planes = []
        @next_id = 1
        @active_id = nil
        @history = []
      end

      def bounds=(range)
        @zmin, @zmax = range.map(&:to_f)
      end

      def add(z, step: 0.0, count: 0)
        snapshot
        plane = Plane.new(@next_id, z.to_f, step.to_f, clamp_count(count))
        @next_id += 1
        @planes << plane
        @active_id = plane.id
        plane
      end

      def find(id)
        @planes.find { |plane| plane.id == id.to_i }
      end

      def active
        find(@active_id)
      end

      # Последняя добавленная — опора для относительного ввода «+500».
      def last
        @planes.last
      end

      def remove(id)
        plane = find(id) or return false
        snapshot
        @planes.delete(plane)
        @active_id = @planes.last && @planes.last.id if @active_id == plane.id
        true
      end

      def set_z(id, z)
        plane = find(id) or return false
        snapshot
        plane.z = z.to_f
        @active_id = plane.id
        true
      end

      def set_array(id, step, count)
        plane = find(id) or return false
        snapshot
        plane.step = step.to_f
        plane.count = clamp_count(count)
        @active_id = plane.id
        true
      end

      def select(id)
        @active_id = id.to_i if find(id)
      end

      def empty?
        @planes.empty?
      end

      def can_undo?
        !@history.empty?
      end

      def undo
        return false if @history.empty?
        rows, @active_id, @next_id = @history.pop
        @planes = rows.map { |row| Plane.new(*row) }
        true
      end

      def inside?(z)
        z >= @zmin - MERGE_TOL && z <= @zmax + MERGE_TOL
      end

      # Отметки всех плоскостей и копий по возрастанию, совпадающие в пределах
      # 0,1 мм объединены (при слиянии остаётся исходная, а не копия).
      def levels
        raw = []
        @planes.each do |plane|
          raw << [plane.z, plane.id, 0]
          next if plane.step.abs < MERGE_TOL
          1.upto(plane.count) { |i| raw << [plane.z + plane.step * i, plane.id, i] }
        end
        raw.sort_by! { |z, id, copy| [z, copy, id] }

        merged = []
        raw.each do |entry|
          prev = merged.last
          if prev && (entry[0] - prev[0]).abs <= MERGE_TOL
            merged[-1] = entry if entry[2].zero? && !prev[2].zero?
            next
          end
          merged << entry
        end

        number = 0
        merged.map do |z, id, copy|
          inside = inside?(z)
          Level.new(z, inside ? (number += 1) : nil, id, copy, inside)
        end
      end

      private

      def clamp_count(count)
        [[count.to_i, 0].max, MAX_COPIES].min
      end

      def snapshot
        @history << [@planes.map(&:to_a), @active_id, @next_id]
        @history.shift if @history.size > MAX_HISTORY
      end

    end # class PlaneSet

  end # module SectionSlicer
end # module BACommunity
