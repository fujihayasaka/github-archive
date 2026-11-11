# typed: true
# frozen_string_literal: true

module Languages
  class BadgeComponent < ApplicationComponent
    include LanguageHelper

    def initialize(name:, color: nil, **args)
      @name, @color, @args = name, color, args

      @color = language_color(Linguist::Language[@name]) unless @color.present?
    end

    private

    def render?
      @name.present?
    end
  end
end
