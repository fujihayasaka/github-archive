# typed: true
# frozen_string_literal: true

module Site
  # The language icons are downloaded from https://simpleicons.org/
  class LanguageIconComponent < ApplicationComponent
    include SvgHelper

    def initialize(language:, size: 24, classes: nil)
      @language = language || "Code"
      @size = size
      @classes = classes
    end
  end
end
