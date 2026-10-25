# Copyright 2026 B&A community
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'sketchup.rb'

module BACommunity
  module SectionSlicer

    HERE = File.dirname(__FILE__).freeze

    require File.join(HERE, 'lang.rb')
    require File.join(HERE, 'strings.rb')
    require File.join(HERE, 'units.rb')
    require File.join(HERE, 'plane_set.rb')
    require File.join(HERE, 'slicer.rb')
    require File.join(HERE, 'area_report.rb')
    require File.join(HERE, 'clipboard.rb')
    require File.join(HERE, 'layout.rb')
    require File.join(HERE, 'plane_tool.rb')
    require File.join(HERE, 'session.rb')

    def self.icon(name)
      ext = Sketchup.platform == :platform_osx ? 'png' : 'svg'
      [File.join(HERE, 'icons', "#{name}_16.#{ext}"), File.join(HERE, 'icons', "#{name}_24.#{ext}")]
    end

    def self.command(name, tip, status, &block)
      cmd = UI::Command.new(SectionSlicer.t(name), &block)
      cmd.small_icon, cmd.large_icon = icon(name == :menu_slice ? 'slicer' : 'table')
      cmd.tooltip = SectionSlicer.t(tip)
      cmd.status_bar_text = SectionSlicer.t(status)
      cmd
    end

    unless file_loaded?(__FILE__)
      slice = command(:menu_slice, :tip_slice, :status_slice) { Session.start }
      report = command(:menu_report, :tip_report, :status_report) { Session.open_report }

      menu = UI.menu('Extensions').add_submenu(EXTENSION_NAME)
      menu.add_item(slice)
      menu.add_item(report)

      toolbar = UI::Toolbar.new(EXTENSION_NAME)
      toolbar.add_item(slice)
      toolbar.add_item(report)
      toolbar.restore

      UI.add_context_menu_handler do |context_menu|
        selection = Sketchup.active_model.selection
        next unless selection.size == 1
        entity = selection.first
        if AreaReport.stored?(entity)
          context_menu.add_item(report)
        elsif Session.instance_like?(entity)
          context_menu.add_item(slice)
        end
      end

      file_loaded(__FILE__)
    end

  end # module SectionSlicer
end # module BACommunity
