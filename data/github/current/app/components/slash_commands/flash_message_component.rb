# typed: true
# frozen_string_literal: true

module SlashCommands
  class FlashMessageComponent < ApplicationComponent
    attr_reader :flash
    def initialize(flash)
      @flash = flash
    end
  end
end
