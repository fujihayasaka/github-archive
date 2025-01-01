# typed: true
# frozen_string_literal: true

module Reactions
  class DropdownComponent < ApplicationComponent
    def self.placeholder(
      inline_with_reactions: true,
      form_context: {},
      p: nil,
      classes: nil,
      px: nil,
      py: nil,
      mr: nil,
      data: {},
      aria: {},
      popover_direction: Reactions::PopoverComponent::POPOVER_DIRECTION_DEFAULT
    )
      new(
        is_placeholder: true,
        target_global_relay_id: nil,
        available_emotions: [],
        reaction_path: nil,
        inline_with_reactions: inline_with_reactions,
        form_context: form_context,
        disabled: true,
        classes: classes,
        p: p,
        px: px,
        py: py,
        mr: mr,
        data: data,
        aria: aria,
        popover_direction: popover_direction
      )
    end

    def initialize(
      target_global_relay_id:,
      available_emotions:,
      reaction_path:,
      viewer_reactions: [],
      inline_with_reactions: true,
      is_placeholder: false,
      disabled: false,
      form_context: {},
      classes: nil,
      focus: false,
      p: nil,
      px: nil,
      py: nil,
      mr: nil,
      data: {},
      aria: {},
      popover_direction: Reactions::PopoverComponent::POPOVER_DIRECTION_DEFAULT
    )
      @target_global_relay_id = target_global_relay_id
      @available_emotions = available_emotions
      @reaction_path = reaction_path
      @viewer_reactions = viewer_reactions
      @is_placeholder = is_placeholder
      @disabled = disabled
      @focus = focus
      @form_context = form_context
      @popover_direction = popover_direction

      @system_arguments = {}
      @system_arguments[:aria] = {
        label: "Add or remove reactions",
        haspopup: true
      }.merge!(aria)
      @system_arguments[:data] = data

      if inline_with_reactions
        @system_arguments[:bg] = :subtle
        @system_arguments[:border] = true
        @system_arguments[:border_color] = :muted
      end

      @system_arguments[:scheme] = inline_with_reactions ? :invisible : :link

      @system_arguments[:classes] = class_names(
        "circle reaction-dropdown-button",
        "reaction-dropdown-button--inline": inline_with_reactions,
        "js-reactions-focus": focus,
        "#{classes}": classes.present?,
      )
      @system_arguments[:p] = p if p
      @system_arguments[:px] = px if px
      @system_arguments[:py] = py if py
      @system_arguments[:mr] = mr if mr
    end

    attr_reader :target_global_relay_id, :available_emotions, :reaction_path, :disabled, :form_context,
      :viewer_reactions, :is_placeholder, :system_arguments, :popover_direction
  end
end
