# typed: true
# frozen_string_literal: true

module Discussions
  class EventGroupComponent < ApplicationComponent
    def initialize(discussion:, group:)
      @group = group
      @discussion = discussion
    end

    private

    attr_reader :group, :discussion

    # Private: Get a verb or phrase to describe what a given event group represents.
    #
    # Returns a String.
    def discussion_event_group_verb
      event_type = group.event_type
      case event_type.to_sym
      when :answer_marked
        any_unmarked = group.events.any?(&:answer_unmarked?)
        if any_unmarked
          "unmarked and re-marked"
        else
          "marked"
        end
      when :answer_unmarked
        any_marked = group.events.any?(&:answer_marked?)
        if any_marked
          "marked then unmarked"
        else
          "unmarked"
        end
      when :answer_verified
        any_unverified = group.events.any?(&:answer_unverified?)
        if any_unverified
          "unverified and re-verified"
        else
          "verified"
        end
      when :answer_unverified
        any_verified = group.events.any?(&:answer_verified?)
        if any_verified
          "verified then unverified"
        else
          "unverified"
        end
      when :locked
        any_unlocked = group.events.any?(&:unlocked?)
        if any_unlocked
          "unlocked and locked"
        else
          "locked"
        end
      when :unlocked
        any_locked = group.events.any?(&:locked?)
        if any_locked
          "locked and unlocked"
        else
          "unlocked"
        end
      else
        event_type.to_s.humanize
      end
    end
  end
end
