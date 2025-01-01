# typed: true
# frozen_string_literal: true

module Primer
  module Experimental
    module SelectMenu
      # SelectMenu lists.
      class ListComponent < Primer::Component # rubocop:disable ViewComponent/EncouragePreviewsForPrimer
        DEFAULT_BORDER_CLASS = :all
        BORDER_CLASSES = {
          all: nil,
          omit_top: "border-top-0",
          none: "SelectMenu-list--borderless",
        }.freeze

        renders_one :message, Primer::Experimental::SelectMenu::MessageComponent
        renders_many :items, Primer::Experimental::SelectMenu::ItemComponent

        attr_accessor :role, :hidden
        attr_reader :title

        # @param loading [Boolean] Whether the content will be a loading message.
        # @param border [Symbol] What kind of border to have around the list element.
        def initialize(loading: false, border: DEFAULT_BORDER_CLASS, role: nil, hidden: false, title: nil, **system_arguments)
          @loading = loading
          @title = title
          @role = role
          @hidden = hidden
          @system_arguments = system_arguments

          @system_arguments[:tag] = :div
          @system_arguments[:classes] = class_names(
            "SelectMenu-list",
            BORDER_CLASSES[border],
            system_arguments[:classes],
          )
        end

        def before_render
          @system_arguments[:role] = role
          @system_arguments[:hidden] = hidden if hidden
        end

        def render?
          items.any? || message.present? || content.present?
        end
      end
    end
  end
end
