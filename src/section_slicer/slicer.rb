# Copyright 2026 B&A community. Licensed under Apache License 2.0.

module BACommunity
  module SectionSlicer

    # Горизонтальные сечения без временной геометрии: грани объекта
    # собираются рекурсивно в мировых координатах, пересекаются с плоскостью
    # z = h собственным расчётом, отрезки сшиваются в контуры, контуры
    # превращаются в грани SketchUp с вырезами. Исходная модель не меняется.
    module Slicer

      STITCH_TOL    = 0.1 / 25.4   # допуск сшивки 0,1 мм
      COLLINEAR_TOL = 0.005 / 25.4 # точка ближе к прямой соседей — лишняя
      PLANE_EPS     = 1.0e-6       # вершина ближе к плоскости считается лежащей на ней
      SIDE_EPS      = 0.05 / 25.4  # отступ от ребра при проверке сторон объединения

      # loops — массивы [x, y, z] мировых точек, первая петля внешняя;
      # body — номер вложенного контекста (тела), из которого взята грань.
      FaceData = Struct.new(:loops, :dx, :dy, :zmin, :zmax, :body)

      # loops — замкнутые простые контуры [[x, y], ...];
      # chains — незамкнутые ломаные (разрывы);
      # regions — замкнутые контуры каждого тела, для проверки «внутри»;
      # bounds — [xmin, ymin, xmax, ymax] или nil для пустого сечения.
      Section = Struct.new(:z, :loops, :chains, :regions, :bounds) do
        def empty?
          loops.empty? && chains.empty?
        end

        def gaps?
          !chains.empty?
        end

        def inside?(x, y)
          regions.any? { |region| region.inside?(x, y) }
        end
      end

      module_function

      # --- Сбор граней --------------------------------------------------

      def collect(entities, transformation, out = [], counter = [0])
        body = counter[0]
        entities.each do |entity|
          case entity
          when Sketchup::Face
            next unless visible?(entity)
            data = face_data(entity, transformation)
            next unless data
            data.body = body
            out << data
          when Sketchup::Group, Sketchup::ComponentInstance
            next unless visible?(entity)
            counter[0] += 1
            collect(entity.definition.entities, transformation * entity.transformation, out, counter)
          end
        end
        out
      end

      # Замкнутость с учётом вложенности: каждое ребро с гранями во всех
      # видимых уровнях ограничивает ровно две грани. Отдельные линии без
      # граней на сечение не влияют и не считаются. Группа из вложенных
      # солидов — тоже тело, хотя Entity Info SketchUp так её не называет.
      def solid?(entities, seen = {})
        has_faces = false
        entities.each do |entity|
          case entity
          when Sketchup::Edge
            count = entity.faces.size
            return false if count == 1 || count > 2
          when Sketchup::Face
            has_faces = true
          when Sketchup::Group, Sketchup::ComponentInstance
            next unless visible?(entity)
            definition = entity.definition
            next if seen[definition]
            seen[definition] = true
            return false unless solid?(definition.entities, seen)
            has_faces = true
          end
        end
        has_faces
      end

      def visible?(entity)
        return false if entity.hidden?
        layer = entity.layer
        layer.nil? || layer.visible?
      end

      def face_data(face, transformation)
        loops = face.loops.map do |loop|
          loop.vertices.map do |vertex|
            point = vertex.position.transform(transformation)
            [point.x.to_f, point.y.to_f, point.z.to_f]
          end
        end
        outer = loops.first
        return nil if outer.nil? || outer.size < 3

        # Нормаль Ньюэлла: устойчива к зеркалу и неравномерному масштабу.
        nx = ny = nz = 0.0
        outer.each_with_index do |a, i|
          b = outer[(i + 1) % outer.size]
          nx += (a[1] - b[1]) * (a[2] + b[2])
          ny += (a[2] - b[2]) * (a[0] + b[0])
          nz += (a[0] - b[0]) * (a[1] + b[1])
        end
        length = Math.sqrt(nx * nx + ny * ny + nz * nz)
        return nil if length.zero?
        # Горизонтальная грань целиком по одну сторону любой плоскости z = h
        # (вершины на самой плоскости относятся к одной стороне) и отрезков
        # не даёт.
        return nil if Math.sqrt(nx * nx + ny * ny) / length < 1.0e-9

        zs = outer.map { |p| p[2] }
        # Линия пересечения грани с горизонтальной плоскостью идёт вдоль
        # Z × n — по ней сортируются точки пересечения.
        FaceData.new(loops, -ny, nx, zs.min, zs.max)
      end

      def bounds(faces)
        return nil if faces.empty?
        xs = []
        ys = []
        zs = []
        faces.each do |face|
          face.loops.first.each do |x, y, z|
            xs << x
            ys << y
            zs << z
          end
        end
        [xs.min, ys.min, zs.min, xs.max, ys.max, zs.max]
      end

      # --- Пересечение --------------------------------------------------

      # Вершина ровно на плоскости относится к нижней стороне: сечение на
      # отметке пола даёт план этажа над ней (h + ε). На верхней отметке
      # объекта — наоборот (h − ε), иначе срез по крыше был бы пустым.
      def segments(faces, h, top)
        result = []
        faces.each do |face|
          next if face.zmax < h - PLANE_EPS || face.zmin > h + PLANE_EPS
          points = []
          face.loops.each do |loop|
            count = loop.size
            loop.each_with_index do |a, i|
              b = loop[(i + 1) % count]
              next if above?(a[2], h, top) == above?(b[2], h, top)
              lo, hi = a[2] < b[2] ? [a, b] : [b, a]
              t = (h - lo[2]) / (hi[2] - lo[2])
              t = 0.0 if t < 0.0
              t = 1.0 if t > 1.0
              points << [lo[0] + (hi[0] - lo[0]) * t, lo[1] + (hi[1] - lo[1]) * t]
            end
          end
          next if points.size < 2
          dx = face.dx
          dy = face.dy
          points.sort_by! { |x, y| x * dx + y * dy }
          (0...(points.size / 2)).each do |k|
            a = points[2 * k]
            b = points[2 * k + 1]
            next if (a[0] - b[0]).abs < 1.0e-9 && (a[1] - b[1]).abs < 1.0e-9
            result << [a[0], a[1], b[0], b[1]]
          end
        end
        result
      end

      def above?(z, h, top)
        d = z - h
        d = 0.0 if d.abs < PLANE_EPS
        top ? d >= 0.0 : d > 0.0
      end

      # --- Сшивка и объединение ------------------------------------------

      # Каждое вложенное тело сшивается отдельно, затем замкнутые контуры
      # тел объединяются: соприкасающиеся и пересекающиеся тела дают один
      # общий контур, как на плане.
      def section(faces, h, zmax)
        top = h >= zmax - PLANE_EPS
        regions = []
        closed = []
        chains = []
        faces.group_by(&:body).each_value do |body_faces|
          graph = Graph.new(segments(body_faces, h, top), xor: true)
          segs, open = graph.split
          chains.concat(open.map { |chain| simplify(chain, false) }.select { |c| c.size >= 2 })
          next if segs.empty?
          regions << Region.new(segs)
          closed << segs
        end

        boundary = closed.size > 1 ? union_boundary(closed.flatten(1), regions) : closed.flatten(1)
        graph = Graph.new(boundary.map { |(a, b)| [a[0], a[1], b[0], b[1]] }, xor: false)
        loops = []
        graph.closed_loops.each do |loop|
          pts = simplify(loop, true)
          loops << pts if pts.size >= 3 && polygon_area(pts).abs > STITCH_TOL**2
        end
        # Остатки с нечётными вершинами после объединения — тоже разрывы.
        chains.concat(graph.open_chains.map { |chain| simplify(chain, false) }.select { |c| c.size >= 2 })

        used = (loops + chains).flatten(1)
        box = if used.empty?
                nil
              else
                xs = used.map(&:first)
                ys = used.map(&:last)
                [xs.min, ys.min, xs.max, ys.max]
              end
        Section.new(h, loops, chains, regions, box)
      end

      # Граница объединения: все отрезки режутся в точках взаимных
      # пересечений и касаний, остаются те, по одну сторону которых
      # материал есть, а по другую — нет.
      def union_boundary(segments, regions)
        pieces = split_all(segments)
        seen = {}
        result = []
        pieces.each do |a, b|
          key = [a, b].map { |p| [(p[0] / STITCH_TOL).round, (p[1] / STITCH_TOL).round] }.sort
          next if seen[key]
          seen[key] = true
          dx = b[0] - a[0]
          dy = b[1] - a[1]
          length = Math.sqrt(dx * dx + dy * dy)
          next if length < STITCH_TOL
          eps = [length * 0.25, SIDE_EPS].min
          mx = (a[0] + b[0]) / 2.0
          my = (a[1] + b[1]) / 2.0
          nx = -dy / length * eps
          ny = dx / length * eps
          left = regions.any? { |r| r.inside?(mx + nx, my + ny) }
          right = regions.any? { |r| r.inside?(mx - nx, my - ny) }
          result << [a, b] if left != right
        end
        result
      end

      # Разрезает отрезки во всех точках пересечения друг с другом, включая
      # T-примыкания и совпадающие участки. Сетка ограничивает число пар.
      def split_all(segments)
        return segments if segments.size < 2
        xs = segments.flat_map { |(a, b)| [a[0], b[0]] }
        ys = segments.flat_map { |(a, b)| [a[1], b[1]] }
        span = [xs.max - xs.min, ys.max - ys.min, STITCH_TOL].max
        cell = span / [Math.sqrt(segments.size).ceil, 1].max
        x0 = xs.min
        y0 = ys.min
        grid = Hash.new { |h, k| h[k] = [] }
        segments.each_with_index do |(a, b), i|
          cx = [(([a[0], b[0]].min - x0 - STITCH_TOL) / cell).floor, (([a[0], b[0]].max - x0 + STITCH_TOL) / cell).floor]
          cy = [(([a[1], b[1]].min - y0 - STITCH_TOL) / cell).floor, (([a[1], b[1]].max - y0 + STITCH_TOL) / cell).floor]
          (cx[0]..cx[1]).each { |gx| (cy[0]..cy[1]).each { |gy| grid[[gx, gy]] << i } }
        end

        params = Array.new(segments.size) { [] }
        checked = {}
        grid.each_value do |ids|
          ids.each_with_index do |i, k|
            ids[(k + 1)..-1].each do |j|
              key = i < j ? i * segments.size + j : j * segments.size + i
              next if checked[key]
              checked[key] = true
              cross_params(segments[i], segments[j], params[i], params[j])
            end
          end
        end

        result = []
        segments.each_with_index do |(a, b), i|
          ts = params[i].sort
          prev = a
          ts.each do |t|
            point = [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t]
            result << [prev, point]
            prev = point
          end
          result << [prev, b]
        end
        result
      end

      def cross_params(s1, s2, out1, out2)
        p = s1[0]
        rx = s1[1][0] - p[0]
        ry = s1[1][1] - p[1]
        q = s2[0]
        sx = s2[1][0] - q[0]
        sy = s2[1][1] - q[1]
        len_r = Math.sqrt(rx * rx + ry * ry)
        len_s = Math.sqrt(sx * sx + sy * sy)
        return if len_r < STITCH_TOL || len_s < STITCH_TOL
        tol_r = STITCH_TOL / len_r
        tol_s = STITCH_TOL / len_s
        denom = rx * sy - ry * sx
        if denom.abs > 1.0e-9 * len_r * len_s
          qpx = q[0] - p[0]
          qpy = q[1] - p[1]
          t = (qpx * sy - qpy * sx) / denom
          u = (qpx * ry - qpy * rx) / denom
          if t > tol_r && t < 1 - tol_r && u > -tol_s && u < 1 + tol_s
            out1 << t
          end
          if u > tol_s && u < 1 - tol_s && t > -tol_r && t < 1 + tol_r
            out2 << u
          end
        end
        # Концы одного отрезка на другом: T-примыкания и общие участки.
        s2.each { |pt| t = param_on(p, rx, ry, len_r, pt); out1 << t if t && t > tol_r && t < 1 - tol_r }
        s1.each { |pt| u = param_on(q, sx, sy, len_s, pt); out2 << u if u && u > tol_s && u < 1 - tol_s }
      end

      def param_on(origin, dx, dy, length, point)
        px = point[0] - origin[0]
        py = point[1] - origin[1]
        return nil if (px * dy - py * dx).abs / length > STITCH_TOL
        (px * dx + py * dy) / (length * length)
      end

      # Граф отрезков со сшивкой вершин в пределах 0,1 мм.
      class Graph

        attr_reader :points, :edges

        # xor: отрезок, встреченный чётное число раз, исчезает — так внутри
        # одного тела гасятся двойные грани.
        def initialize(raw, xor:)
          @points = []
          @grid = {}
          counts = Hash.new(0)
          raw.each do |ax, ay, bx, by|
            i = index(ax, ay)
            j = index(bx, by)
            next if i == j
            counts[i < j ? [i, j] : [j, i]] += 1
          end
          @edges = xor ? counts.select { |_, n| n.odd? }.keys : counts.keys
          @adjacency = Hash.new { |hash, key| hash[key] = [] }
          @edges.each_with_index do |(i, j), e|
            @adjacency[i] << e
            @adjacency[j] << e
          end
        end

        # → [отрезки замкнутых компонент [[x, y], [x, y]], незамкнутые ломаные]
        def split
          closed = []
          open = []
          components.each do |vertices, comp_edges|
            if vertices.all? { |v| @adjacency[v].size.even? }
              comp_edges.each { |e| closed << @edges[e].map { |id| @points[id] } }
            else
              open.concat(trace_chains(comp_edges).map { |ids| ids.map { |id| @points[id] } })
            end
          end
          [closed, open]
        end

        def closed_loops
          components.select { |vertices, _| vertices.all? { |v| @adjacency[v].size.even? } }
                    .flat_map { |_, comp_edges| trace_loops(comp_edges) }
                    .map { |ids| ids.map { |id| @points[id] } }
        end

        def open_chains
          components.reject { |vertices, _| vertices.all? { |v| @adjacency[v].size.even? } }
                    .flat_map { |_, comp_edges| trace_chains(comp_edges) }
                    .map { |ids| ids.map { |id| @points[id] } }
        end

        private

        def index(x, y)
          tol = STITCH_TOL
          cx = (x / tol).floor
          cy = (y / tol).floor
          (-1..1).each do |ox|
            (-1..1).each do |oy|
              (@grid[[cx + ox, cy + oy]] || []).each do |id|
                px, py = @points[id]
                return id if (px - x)**2 + (py - y)**2 <= tol * tol
              end
            end
          end
          @points << [x, y]
          (@grid[[cx, cy]] ||= []) << @points.size - 1
          @points.size - 1
        end

        def components
          @components ||= begin
            seen = {}
            result = []
            @adjacency.each_key do |start|
              next if seen[start]
              seen[start] = true
              stack = [start]
              vertices = []
              until stack.empty?
                v = stack.pop
                vertices << v
                @adjacency[v].each do |e|
                  @edges[e].each do |w|
                    next if seen[w]
                    seen[w] = true
                    stack << w
                  end
                end
              end
              result << [vertices, vertices.flat_map { |v| @adjacency[v] }.uniq]
            end
            result
          end
        end

        # Компонента с чётными степенями раскладывается на простые циклы:
        # если обход вернулся в уже пройденную вершину, петля отрезается.
        def trace_loops(comp_edges)
          unused = comp_edges.each_with_object({}) { |e, h| h[e] = true }
          loops = []
          until unused.empty?
            first = unused.keys.first
            unused.delete(first)
            a, b = @edges[first]
            path = [a, b]
            position = { a => 0, b => 1 }
            current = b
            loop do
              e = @adjacency[current].find { |candidate| unused[candidate] }
              break unless e
              unused.delete(e)
              i, j = @edges[e]
              nxt = i == current ? j : i
              if position.key?(nxt)
                start = position[nxt]
                loops << path[start..-1]
                path[(start + 1)..-1].each { |v| position.delete(v) }
                path = path[0..start]
                break if path.size == 1
                current = nxt
              else
                position[nxt] = path.size
                path << nxt
                current = nxt
              end
            end
          end
          loops
        end

        def trace_chains(comp_edges)
          unused = comp_edges.each_with_object({}) { |e, h| h[e] = true }
          chains = []
          until unused.empty?
            ends = unused.keys.flat_map { |e| @edges[e] }.uniq
            start = ends.find { |v| @adjacency[v].count { |e| unused[e] }.odd? } || ends.first
            path = [start]
            current = start
            while (e = @adjacency[current].find { |candidate| unused[candidate] })
              unused.delete(e)
              i, j = @edges[e]
              current = i == current ? j : i
              path << current
            end
            chains << path
          end
          chains
        end

      end # class Graph

      # Замкнутые контуры одного тела с быстрой проверкой «точка внутри»
      # по чётно-нечётному правилу: отрезки разложены по полосам Y.
      class Region

        def initialize(segments)
          ys = segments.flat_map { |(a, b)| [a[1], b[1]] }
          xs = segments.flat_map { |(a, b)| [a[0], b[0]] }
          @xmin, @xmax = xs.minmax
          @ymin, @ymax = ys.minmax
          @count = [[Math.sqrt(segments.size).ceil, 1].max, 1024].min
          @step = (@ymax - @ymin) / @count
          @step = 1.0 if @step <= 0
          @bands = Array.new(@count) { [] }
          segments.each do |seg|
            lo, hi = [seg[0][1], seg[1][1]].minmax
            (band(lo)..band(hi)).each { |i| @bands[i] << seg }
          end
        end

        def inside?(x, y)
          return false if x < @xmin || x > @xmax || y < @ymin || y > @ymax
          inside = false
          @bands[band(y)].each do |(ax, ay), (bx, by)|
            next if (ay > y) == (by > y)
            cx = ax + (y - ay) * (bx - ax) / (by - ay)
            inside = !inside if cx > x
          end
          inside
        end

        private

        def band(y)
          i = ((y - @ymin) / @step).floor
          i < 0 ? 0 : (i >= @count ? @count - 1 : i)
        end

      end # class Region

      # Убирает промежуточные точки на прямых участках за один проход.
      def simplify(points, closed)
        pts = []
        points.each do |p|
          pts.pop while pts.size >= 2 && redundant?(pts[-2], pts[-1], p)
          pts << p
        end
        return pts unless closed
        # Стык начала и конца замкнутого контура.
        loop do
          break if pts.size <= 3
          if redundant?(pts[-2], pts[-1], pts[0])
            pts.pop
          elsif redundant?(pts[-1], pts[0], pts[1])
            pts.shift
          else
            break
          end
        end
        pts
      end

      def redundant?(a, p, b)
        abx = b[0] - a[0]
        aby = b[1] - a[1]
        len2 = abx * abx + aby * aby
        return true if len2 < 1.0e-18
        t = ((p[0] - a[0]) * abx + (p[1] - a[1]) * aby) / len2
        return false if t <= 0.0 || t >= 1.0
        cross = (p[0] - a[0]) * aby - (p[1] - a[1]) * abx
        cross.abs / Math.sqrt(len2) < COLLINEAR_TOL
      end

      def polygon_area(points)
        sum = 0.0
        points.each_with_index do |(x1, y1), i|
          x2, y2 = points[(i + 1) % points.size]
          sum += x1 * y2 - x2 * y1
        end
        sum / 2.0
      end

      # --- Геометрия SketchUp -------------------------------------------

      # Строит грани сечения в entities на z = 0 (координаты XY — мировые).
      # Возвращает { faces: [...], chains: [[длина, [edges]], ...] }.
      def fill(entities, section)
        built = false
        if defined?(Sketchup::EntitiesBuilder) && entities.respond_to?(:build)
          nested = nest(section)
          if nested
            begin
              entities.build do |builder|
                nested.each { |outer, holes| builder.add_face(points3d(outer), holes: holes.map { |h| points3d(h) }) }
              end
              built = true
            rescue StandardError => e
              puts "Section Slicer: EntitiesBuilder fallback: #{e.message}"
              entities.clear!
            end
          end
        end
        fill_by_splitting(entities, section) unless built

        faces = entities.grep(Sketchup::Face)
        faces.each { |face| face.reverse! if face.normal.z < 0 }

        chains = section.chains.map do |chain|
          edges = entities.add_edges(points3d(chain)) || []
          [edges.sum(&:length).to_f, edges]
        end
        { faces: faces, chains: chains }
      end

      def points3d(points)
        points.map { |x, y| Geom::Point3d.new(x, y, 0) }
      end

      # SketchUp 2021: каждая петля — add_face, вложенные петли режут
      # грани; грани над отверстиями затем удаляются по правилу «внутри».
      def fill_by_splitting(entities, section)
        section.loops.sort_by { |loop| -polygon_area(loop).abs }.each do |loop|
          pts = points3d(loop)
          begin
            entities.add_face(pts)
          rescue ArgumentError
            entities.add_edges(pts + [pts.first])
          end
        end
        entities.grep(Sketchup::Face).each do |face|
          x, y = sample(face)
          face.erase! unless x && section.inside?(x, y)
        end
        entities.grep(Sketchup::Edge).each { |edge| edge.erase! if edge.valid? && edge.faces.empty? }
      end

      # Раскладывает контуры на внешние (материал внутри) и отверстия,
      # каждому отверстию — наименьший охватывающий внешний контур.
      # → [[outer, [hole, ...]], ...] или nil, если вложенность неясна.
      def nest(section)
        outers = []
        holes = []
        section.loops.each do |loop|
          ccw = polygon_area(loop) > 0
          x, y = edge_probe(loop, ccw ? 1.0 : -1.0)
          (section.inside?(x, y) ? outers : holes) << loop
        end
        nested = outers.sort_by { |loop| polygon_area(loop).abs }.map { |loop| [loop, [], box2d(loop)] }
        holes.each do |hole|
          ccw = polygon_area(hole) > 0
          x, y = edge_probe(hole, ccw ? -1.0 : 1.0)
          parent = nested.find do |outer, _, (x0, y0, x1, y1)|
            x >= x0 && x <= x1 && y >= y0 && y <= y1 && point_in_polygon?(outer, x, y)
          end
          return nil unless parent
          parent[1] << hole
        end
        nested.map { |outer, inner, _| [outer, inner] }
      end

      # Точка у середины самого длинного ребра: side +1 — слева по обходу.
      def edge_probe(loop, side)
        best = nil
        loop.each_with_index do |a, i|
          b = loop[(i + 1) % loop.size]
          length = Math.sqrt((b[0] - a[0])**2 + (b[1] - a[1])**2)
          best = [a, b, length] if best.nil? || length > best[2]
        end
        a, b, length = best
        eps = [length * 0.25, SIDE_EPS].min * side
        dx = (b[0] - a[0]) / length
        dy = (b[1] - a[1]) / length
        [(a[0] + b[0]) / 2.0 - dy * eps, (a[1] + b[1]) / 2.0 + dx * eps]
      end

      def box2d(loop)
        xs = loop.map(&:first)
        ys = loop.map(&:last)
        [xs.min, ys.min, xs.max, ys.max]
      end

      def point_in_polygon?(loop, x, y)
        inside = false
        loop.each_with_index do |(ax, ay), i|
          bx, by = loop[(i + 1) % loop.size]
          next if (ay > y) == (by > y)
          inside = !inside if ax + (y - ay) * (bx - ax) / (by - ay) > x
        end
        inside
      end

      # Точка чуть внутрь грани от середины самого длинного ребра её внешнего
      # контура: без триангуляции, которая дорога для граней с сотнями
      # отверстий. Внешний контур обходится против часовой стрелки, если
      # смотреть со стороны нормали, — внутренняя сторона слева.
      def sample(face)
        vertices = face.outer_loop.vertices.map(&:position)
        return nil if vertices.size < 3
        best = nil
        vertices.each_with_index do |a, i|
          b = vertices[(i + 1) % vertices.size]
          length = a.distance(b).to_f
          best = [a, b, length] if best.nil? || length > best[2]
        end
        a, b, length = best
        return nil if length <= 0
        side = face.normal.z < 0 ? -1.0 : 1.0
        eps = [length * 0.25, SIDE_EPS].min * side
        dx = (b.x - a.x) / length
        dy = (b.y - a.y) / length
        [(a.x + b.x) / 2.0 - dy * eps, (a.y + b.y) / 2.0 + dx * eps]
      end

    end # module Slicer

  end # module SectionSlicer
end # module BACommunity
