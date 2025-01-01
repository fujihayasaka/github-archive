# typed: true
# frozen_string_literal: true

module SlashCommands
  class HeaderComponent < ApplicationComponent
    attr_reader :breadcrumbs
    def initialize(breadcrumbs = [])
      @breadcrumbs = breadcrumbs
    end
  end
end
