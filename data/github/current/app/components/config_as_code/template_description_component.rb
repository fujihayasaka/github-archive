# typed: true
# frozen_string_literal: true

module ConfigAsCode
  class TemplateDescriptionComponent < ApplicationComponent

    MODES = [
      :view,
      :edit
    ].freeze

    attr_reader :label, :description, :docs_url, :mode, :system_arguments

    def initialize(label, description, docs_url, mode: :view, **system_arguments)
      @label = label
      @description = description
      @docs_url = docs_url
      @mode = fetch_or_fallback(MODES, mode, :view)
      @system_arguments = system_arguments
    end
  end
end
