# typed: true
# frozen_string_literal: true

module Settings
  class FixedWidthFontComponent < ApplicationComponent
    attr_reader :user

    def initialize(user:)
      @user = user
    end
  end
end
