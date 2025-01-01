# typed: true
# frozen_string_literal: true

module Dependabot
  class UpdateJobStateIconComponent < ApplicationComponent
    attr_reader :state

    def initialize(state:)
      @state = state
    end
  end
end
