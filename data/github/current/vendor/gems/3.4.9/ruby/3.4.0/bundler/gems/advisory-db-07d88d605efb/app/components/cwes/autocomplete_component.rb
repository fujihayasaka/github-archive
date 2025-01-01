# frozen_string_literal: true

module CWEs
  class AutocompleteComponent < ApplicationComponent
    attr_reader :cwes, :name_prefix

    def initialize(cwes:, name_prefix:, disabled: false)
      @cwes = cwes
      @name_prefix = name_prefix
      @disabled = disabled
    end
  end
end
