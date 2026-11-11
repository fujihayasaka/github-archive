# typed: true
# frozen_string_literal: true

module Reactions
  class PopoverComponent < ApplicationComponent
    POPOVER_DIRECTION_OPTIONS = %w[ne e se s sw w].freeze
    POPOVER_DIRECTION_DEFAULT = "w".freeze

    def initialize(
      reaction_path:,
      available_emotions:,
      target_global_relay_id:,
      viewer_reactions:,
      form_context: {},
      new_style_reactions: true,
      popover_direction: POPOVER_DIRECTION_DEFAULT
    )
      @reaction_path = reaction_path
      @target_global_relay_id = target_global_relay_id
      @viewer_reactions = viewer_reactions
      @available_emotions = available_emotions
      @form_context = form_context
      @new_style_reactions = new_style_reactions
      @popover_direction = fetch_or_fallback(POPOVER_DIRECTION_OPTIONS, popover_direction, POPOVER_DIRECTION_DEFAULT)
    end

    private

    attr_reader :new_style_reactions, :reaction_path, :target_global_relay_id, :viewer_reactions, :form_context,
      :available_emotions, :popover_direction

    def reacted_to?(content)
      @viewer_reactions.include?(content)
    end

    def width
      available_emotions.length <= 6 ? "140px" : "150px"
    end

    def columns
      available_emotions.length <= 6 ? 4 : 3
    end

    def button_class_names(emotion)
      class_names(
        "btn-link",
        "flex-content-center",
        "flex-items-center",
        "no-underline",
        "add-reactions-options-item",
        "js-reaction-option-item",
        "js-optimistic-reaction-render-button",
      )
    end

    def label_content(emotion)
      if reacted_to?(emotion.content)
        "Undo #{emotion.pronounceable_label} reaction"
      else
        "#{emotion.pronounceable_label}"
      end
    end

    def button_arguments(emotion)
      args = {
        name: "input[content]",
        border_radius: 0,
        type: :submit,
        role: "menuitem",
        classes: button_class_names(emotion),
        col: columns,
        data: { "reaction-label": emotion.label.capitalize, "reaction-content": emotion.content },
        aria: { label: label_content(emotion) },
        value: "#{emotion.platform_enum} #{reacted_to?(emotion.content) ? "unreact" : "react"}",
        border_color: reacted_to?(emotion.content) ? :default : nil,
        bg: reacted_to?(emotion.content) ? :accent : nil,
        box_shadow: :none,
      }

      args[:border] = true if reacted_to?(emotion.content)
      args
    end

    def popover_direction_class
      "dropdown-menu-#{popover_direction}"
    end
  end
end
