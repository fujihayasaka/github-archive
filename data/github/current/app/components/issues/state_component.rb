# typed: true
# frozen_string_literal: true

module Issues
  class StateComponent < ApplicationComponent
    STATE_OPTIONS = [:open, :closed]

    def initialize(state:, state_reason: nil, size: Primer::Beta::State::SIZE_DEFAULT, **args)
      @state = state
      @state_reason = state_reason
      @size = size
      @args = args
    end

    private

    def render?
      STATE_OPTIONS.include?(@state)
    end

    def unplanned_or_duplicate_closure?
      @state == :closed && (@state_reason == "NOT_PLANNED" || @state_reason == "DUPLICATE")
    end

    def label
      if @state == :closed && @state_reason == "NOT_PLANNED"
        "Closed as not planned"
      elsif @state == :closed && @state_reason == "DUPLICATE"
        "Closed as duplicate"
      else
        @state.to_s.capitalize
      end
    end

    def color
      case @state
      when :open
        :open
      when :closed
        unplanned_or_duplicate_closure? ? :default : :merged
      end
    end

    def title
      "Status: #{label}"
    end

    def octicon_name
      case @state
      when :open
        "issue-opened"
      when :closed
        unplanned_or_duplicate_closure? ? "skip" : "issue-closed"
      end
    end
  end
end
