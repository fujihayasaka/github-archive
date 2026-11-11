# typed: true
# frozen_string_literal: true

module PullRequests::TimelineEvents
  class CommitStatusChecksComponent < ApplicationComponent
    include StatusHelper
    include PullRequestsHelper

    attr_reader :pull_request, :issue_event

    def initialize(pull_request:, issue_event:)
      @pull_request = pull_request
      @issue_event = issue_event
    end

    private

    memoize def commit_status
      if issue_event.event == "merged"
        pull_request.async_status_at_merge.sync
      elsif issue_event.event == "removed_from_merge_queue"
        commit_oid = issue_event.before_commit_oid
        pull_request.status_at_commit(commit_oid)
      end
    end

    memoize def contexts
      if commit_status
        commit_status.async_contexts_with_no_spammy_creators.sync
      else
        []
      end
    end

    memoize def status_summary
      merge_status_summary(contexts.map(&:state))
    end
  end
end
