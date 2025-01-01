# typed: true
# frozen_string_literal: true

module Reactions
  class ReactionButtonComponent < ApplicationComponent
    # emotion: An Emotion class instance
    def initialize(
      emotion:,
      disabled: false,
      id: nil,
      index: nil,
      title: nil,
      in_popover: false,
      user_has_reacted: false,
      test_selector: nil,
      focus: false,
      data: {},
      aria: {},
      mr: nil,
      mb: nil,
      button_role_checkbox: nil
    )
      @emotion = emotion
      @value = "#{emotion.platform_enum} #{ user_has_reacted ? 'unreact' : 'react' }"
      @disabled = disabled
      @id = id || "#{css_identifier}-#{SecureRandom.hex(3)}"
      @index = index
      @title = title
      @focus = focus
      @system_arguments = {}
      @system_arguments[:data] = {
        "button-index-position": index,
        "reaction-label": emotion.label.capitalize,
        "reaction-content": emotion.content,
      }.merge!(data)
      @system_arguments[:test_selector] = test_selector

      @system_arguments[:color] = :muted if !user_has_reacted

      @system_arguments[:scheme] = in_popover ? :invisible : :link
      @system_arguments[:justify_content] = :center if in_popover
      @system_arguments[:align_items] = in_popover ? :center : :baseline
      @system_arguments[:mr] = mr if mr
      @system_arguments[:mb] = mb if mb

      if button_role_checkbox
        @system_arguments[:role] = "menuitemcheckbox"
        @system_arguments[:aria] = {
          checked: user_has_reacted,
        }.merge!(aria)
      else
        @system_arguments[:aria] = {
          pressed: user_has_reacted,
        }.merge!(aria)
      end

      @system_arguments[:border_radius] = 2 if in_popover

      @system_arguments[:classes] = class_names(
        "social-reaction-summary-item js-reaction-group-button" => !in_popover,
        "dropdown-item dropdown-item-reaction" => in_popover,
        "tooltipped tooltipped-multiline" => !in_popover && !title.present? && aria[:label].present?,
        "user-has-reacted" => user_has_reacted,
        "js-reactions-focus" => focus
      )
    end

    attr_reader :disabled, :value, :id, :index, :title, :system_arguments
  end
end
