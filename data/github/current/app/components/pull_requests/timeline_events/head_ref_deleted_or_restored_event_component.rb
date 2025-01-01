# typed: true
# frozen_string_literal: true

module PullRequests::TimelineEvents
  class HeadRefDeletedOrRestoredEventComponent < ApplicationComponent
    include ResilienceHelper
    attr_reader :issue_event, :head_ref_name, :pull_request

    def initialize(issue_event:, pull_request:)
      @issue_event = issue_event
      @pull_request = pull_request
      @head_ref_name = pull_request.display_head_ref_name
    end

    def deleted?
      issue_event.event == "head_ref_deleted"
    end

    def action
      if deleted?
        "deleted"
      else
        "restored"
      end
    end

    def can_restore_head_ref?
      with_async_database_error_fallback(pull_request.async_head_ref_restorable_by?(current_user), fallback: false).sync
    end
  end
end
