# Copyright 2026 B&A community. Licensed under Apache License 2.0.

module BACommunity
  module SectionSlicer

    # Буфер обмена из Ruby: не зависит от фокуса и разрешений CEF.
    # Windows — WinAPI через Fiddle, сразу текст (TSV) и HTML: Excel берёт
    # HTML и оставляет текстовые ячейки текстом. macOS — pbcopy, только TSV.
    module Clipboard

      CF_UNICODETEXT = 13
      GMEM_MOVEABLE  = 0x0002

      module_function

      # → true, если таблица в буфере.
      def copy(text, html = nil)
        if Sketchup.platform == :platform_win
          copy_windows(text, html)
        else
          IO.popen({ 'LANG' => 'en_US.UTF-8' }, 'pbcopy', 'w') { |io| io.write(text) }
          $?.success?
        end
      rescue StandardError, LoadError => e
        puts "Section Slicer clipboard: #{e.class}: #{e.message}"
        false
      end

      def win
        @win ||= begin
          require 'fiddle'
          user32 = Fiddle.dlopen('user32')
          kernel32 = Fiddle.dlopen('kernel32')
          ptr = Fiddle::TYPE_VOIDP
          int = Fiddle::TYPE_INT
          f = ->(lib, name, args, ret) { Fiddle::Function.new(lib[name], args, ret) }
          {
            open: f.call(user32, 'OpenClipboard', [ptr], int),
            empty: f.call(user32, 'EmptyClipboard', [], int),
            close: f.call(user32, 'CloseClipboard', [], int),
            set: f.call(user32, 'SetClipboardData', [Fiddle::TYPE_UINT, ptr], ptr),
            register: f.call(user32, 'RegisterClipboardFormatW', [ptr], Fiddle::TYPE_UINT),
            alloc: f.call(kernel32, 'GlobalAlloc', [Fiddle::TYPE_UINT, Fiddle::TYPE_SIZE_T], ptr),
            lock: f.call(kernel32, 'GlobalLock', [ptr], ptr),
            unlock: f.call(kernel32, 'GlobalUnlock', [ptr], int),
            free: f.call(kernel32, 'GlobalFree', [ptr], ptr)
          }
        end
      end

      def copy_windows(text, html)
        api = win
        opened = false
        3.times do
          opened = api[:open].call(nil) != 0
          break if opened
          sleep 0.05
        end
        return false unless opened
        begin
          api[:empty].call
          ok = put(api, CF_UNICODETEXT, (text + "\0").encode('UTF-16LE'))
          if html
            format = api[:register].call("HTML Format\0".encode('UTF-16LE'))
            put(api, format, cf_html(html) + "\0") if format != 0
          end
          ok
        ensure
          api[:close].call
        end
      end

      def put(api, format, data)
        bytes = data.b
        handle = api[:alloc].call(GMEM_MOVEABLE, bytes.bytesize)
        return false if handle.null?
        target = api[:lock].call(handle)
        target[0, bytes.bytesize] = bytes
        api[:unlock].call(handle)
        return true unless api[:set].call(format, handle).null?
        api[:free].call(handle)
        false
      end

      # Формат CF_HTML: заголовок с байтовыми смещениями UTF-8.
      def cf_html(fragment)
        head = "Version:0.9\r\nStartHTML:%010d\r\nEndHTML:%010d\r\nStartFragment:%010d\r\nEndFragment:%010d\r\n"
        prefix = "<html><head><meta charset=\"utf-8\"></head><body>\r\n<!--StartFragment-->"
        suffix = "<!--EndFragment-->\r\n</body></html>"
        body = fragment.encode('UTF-8').b
        header_size = format(head, 0, 0, 0, 0).bytesize
        start_html = header_size
        start_fragment = start_html + prefix.bytesize
        end_fragment = start_fragment + body.bytesize
        end_html = end_fragment + suffix.bytesize
        (format(head, start_html, end_html, start_fragment, end_fragment) + prefix).b + body + suffix.b
      end

    end # module Clipboard

  end # module SectionSlicer
end # module BACommunity
