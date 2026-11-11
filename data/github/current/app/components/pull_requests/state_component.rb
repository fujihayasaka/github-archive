# typed: true
# frozen_string_literal: true

module PullRequests
  class StateComponent < ApplicationComponent
    include OcticonsHelper

    STATE_OPTIONS = [:open, :merged, :closed, :archived]

    def initialize(state:, is_draft: false, is_queued: false, is_archived: false, size: Primer::Beta::State::SIZE_DEFAULT, **args)
      @state = is_archived ? :archived : state
      @is_draft, @is_queued, @size, @args = is_draft, is_queued, size, args
    end

    private

    def render?
      STATE_OPTIONS.include?(@state)
    end

    def octicon_height
      @size == :small ? 14 : 16
    end

    def label
      if @state == :archived
        "Archived"
      elsif @state == :open && @is_draft
        "Draft"
      elsif @state == :open && @is_queued
        "Queued"
      else
        @state.to_s.capitalize
      end
    end

    def color
      case @state
      when :archived
        :default
      when :closed
        :closed
      when :merged
        :merged
      when :open
        if @is_draft || @is_queued
          :default
        else
          :open
        end
      end
    end

    def title
      "Status: #{label}"
    end

    def class_name
      if @state == :open && @is_queued
        "bgColor-attention-emphasis pull-request-queued-state"
      end
    end

    def octicon_name
      case @state
      when :archived
        "archive"
      when :merged
        "git-merge"
      when :open
        return "git-pull-request-draft" if @is_draft
        return "git-merge-queue" if @is_queued

        "git-pull-request"
      when :closed
        "git-pull-request-closed"
      end
    end
  end
end
