# typed: true
# frozen_string_literal: true

module SlashCommands
  class CommandResponseComponent < ApplicationComponent
    attr_reader :type, :component, :footer, :reload_suggestions, :submit_form, :custom_event
    alias_method :reload_suggestions?, :reload_suggestions

    def initialize(type:, component:, footer: nil, reload_suggestions: false, submit_form: nil, custom_event: nil)
      @type = type
      @component = component
      @footer = footer
      @reload_suggestions = reload_suggestions
      @submit_form = submit_form
      @custom_event = custom_event
    end
  end
end
