# typed: true
# frozen_string_literal: true

module Repositories
  class DeploymentStatusComponent < ApplicationComponent
    STATE_DEFAULT = :default
    STATE_MAPPINGS = {
      STATE_DEFAULT => :secondary,
      :abandoned => :secondary,
      :inactive => :secondary,
      :destroyed => :secondary,
      :active => :success,
      :error => :danger,
      :failure => :danger,
      :in_progress => :warning,
      :pending => :warning,
      :waiting => :warning,
      :queued => :warning,
    }.freeze

    def initialize(state: STATE_DEFAULT, **args)
      @state, @args = state, args

      @args[:scheme] = STATE_MAPPINGS[fetch_or_fallback(STATE_MAPPINGS.keys, state.to_s.downcase.to_sym, STATE_DEFAULT)]
    end

    private

    def render?
      !@state.nil?
    end
  end
end
