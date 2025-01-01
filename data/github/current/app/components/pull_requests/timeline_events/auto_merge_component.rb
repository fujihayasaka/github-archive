# typed: true
# frozen_string_literal: true

module PullRequests::TimelineEvents
  class AutoMergeComponent < ApplicationComponent
    EVENTS = {
      auto_merge_disabled: "auto_merge_disabled",
      auto_merge_enabled: "auto_merge_enabled",
      auto_squash_enabled: "auto_squash_enabled",
      auto_rebase_enabled: "auto_rebase_enabled"
    }

    attr_reader :issue_event

    def initialize(issue_event:)
      @issue_event = issue_event
    end

    memoize def reason_code
      @issue_event.message
    end

    memoize def reason
      @reason = ::AutoMergeRequest.reason_message(reason_code.to_sym) if reason_code
    end

    memoize def automatically_disabled?
      reason_code.present? && reason_code != "manually_disabled"
    end

    def octicon_symbol
      "git-pull-request"
    end

    def action_message
      case issue_event.event
      when EVENTS[:auto_merge_disabled]
        "disabled auto-merge"
      when EVENTS[:auto_merge_enabled]
        "enabled auto-merge"
      when EVENTS[:auto_squash_enabled]
        "enabled auto-merge (squash)"
      when EVENTS[:auto_rebase_enabled]
        "enabled auto-merge (rebase)"
      end
    end
  end
end
