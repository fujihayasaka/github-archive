# typed: true
# frozen_string_literal: true

module Dependabot
  class UpdateJobStateIconComponent < ApplicationComponent
    attr_reader :state, :warnings

    def initialize(state:, warnings: [])
      @state = state
      @warnings = warnings
    end
  end
end
