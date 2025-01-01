# typed: true
# frozen_string_literal: true

module Statuses
  # This is the little colored icon that appears next to commits in a timeline.
  class IconView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    include StatusHelper
    include DropdownHelper
    include ActionView::Helpers::TagHelper # for class_names

    attr_reader :combined_status
    attr_reader :dropdown_class

    # Override tooltip and dropdown direction with custom class.
    attr_reader :tooltip_direction
    attr_reader :dropdown_direction

    def any_statuses?
      combined_status && combined_status.any?
    end

    def state
      combined_status.state
    end

    def tooltip_class
      "tooltipped-#{tooltip_direction || "e"}"
    end

    def dropdown_classes
      class_names(dropdown_class, dropdown_menu_class(dropdown_direction || "e"))
    end
  end
end
