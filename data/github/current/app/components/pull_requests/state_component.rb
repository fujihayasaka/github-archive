# typed: true
# frozen_string_literal: true

module PullRequests
  class StateComponent < ApplicationComponent
    include OcticonsHelper

    STATE_OPTIONS = [:open, :merged, :closed]

    def initialize(state:, is_draft: false, size: Primer::Beta::State::SIZE_DEFAULT, **args)
      @state, @is_draft, @size, @args = state, is_draft, size, args
    end

    private

    def render?
      STATE_OPTIONS.include?(@state)
    end

    def octicon_height
      @size == :small ? 14 : 16
    end

    def label
      if @state == :open && @is_draft
        "Draft"
      else
        @state.to_s.capitalize
      end
    end

    def color
      case @state
      when :closed
        :closed
      when :merged
        :merged
      when :open
        if @is_draft
          :default
        else
          :open
        end
      end
    end

    def title
      "Status: #{label}"
    end

    def octicon_name
      case @state
      when :merged
        "git-merge"
      when :open
        @is_draft ? "git-pull-request-draft" : "git-pull-request"
      when :closed
        "git-pull-request-closed"
      end
    end
  end
end
