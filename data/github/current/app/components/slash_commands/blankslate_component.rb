# typed: true
# frozen_string_literal: true

module SlashCommands
  class BlankslateComponent < ApplicationComponent
    attr_reader :breadcrumbs, :title, :description

    def initialize(title:, breadcrumbs: [], description: nil, is_error: false)
      @breadcrumbs = breadcrumbs
      @title = title
      @description = description
    end
  end
end
