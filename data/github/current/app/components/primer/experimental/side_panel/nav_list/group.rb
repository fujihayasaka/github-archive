# typed: true
# frozen_string_literal: true

module Primer
  module Experimental
    class SidePanel::NavList::Group < Primer::Beta::NavList::Group
      status :experimental

      renders_one :filter, lambda { |**system_arguments|
        T.bind(self, Primer::Experimental::SidePanel::NavList::Group)

        system_arguments[:input_id] = input_id
        system_arguments[:src] = group_arguments.dig(:data, :src)

        Primer::Experimental::SidePanel::NavList::Group::Filter.new(**system_arguments)
      }

      renders_one :experimental_show_more_item, lambda { |component_klass: Primer::Beta::NavList::Item, **system_arguments|
        T.bind(self, Primer::Beta::NavList::Group)
        system_arguments[:classes] = class_names(
          @item_classes,
          system_arguments[:classes]
        )

        system_arguments[:id] ||= self.class.generate_id(base_name: "item")
        system_arguments[:hidden] = false
        system_arguments[:href] = "#"
        system_arguments[:data] ||= {}
        system_arguments[:data][:target] = "internal-nav-list-group.showMoreItem"
        system_arguments[:data][:action] = "click:internal-nav-list-group#showMore"
        system_arguments[:data][:"current-page"] = "1"
        system_arguments[:label_arguments] = {
          **system_arguments[:label_arguments] || {},
          color: system_arguments[:label_arguments][:color] || :accent
        }

        component_klass.new(list: self, **system_arguments)
      }

      attr_reader :group_arguments

      def initialize(**system_arguments)
        @group_arguments = system_arguments[:group_arguments] || {}
        system_arguments[:data] ||= {}
        system_arguments[:data][:target] = "internal-nav-list-group.list"
        super(**system_arguments)
      end

      def items
        [*super, experimental_show_more_item].tap(&:compact!)
      end

      def input_id
        return @input_id if defined?(@input_id)
        @input_id ||= self.class.generate_id(base_name: "input")
        @group_arguments[:data] = {} unless @group_arguments[:data]
        @group_arguments[:data][:input_id] = @input_id
        @input_id
      end
    end
  end
end
