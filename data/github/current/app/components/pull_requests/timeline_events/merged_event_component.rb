# typed: true
# frozen_string_literal: true

module PullRequests::TimelineEvents
  class MergedEventComponent < ApplicationComponent
    include StatusHelper
    include PullRequestsHelper
    include ResilienceHelper

    attr_reader :issue_event, :pull_request, :repository

    def initialize(issue_event:, pull_request:)
      @issue_event = issue_event
      @pull_request = pull_request
      @repository = pull_request.repository
    end

    memoize def status_at_merge
      pull_request.async_status_at_merge.sync
    end

    memoize def contexts
      status_at_merge.async_contexts_with_no_spammy_creators.sync
    end

    memoize def commit
      issue_event.commit
    end

    def viewer_can_revert?
      with_database_error_fallback(fallback: false) do
        issue_event.async_revertable_by?(current_user).sync && authorized_to_update_revert_branch?
      end
    end

    def authorized_to_update_revert_branch?
      policy_evaluator = pull_request.revert_branch_rule_evaluator
      return true unless policy_evaluator

      policy_evaluator.authorized?(current_user)
    end

    def revert_path
      pull_request.async_revert_path_uri.sync
    end

    def context_states
      return [] unless status_at_merge

      @context_states ||= contexts.map { |ctx| ctx.state }
    end

    memoize def status_summary
      merge_status_summary(context_states)
    end

    def merge_queue?
      %w(merge_queue merge_queue_merge).include?(issue_event.message)
    end

    def api_merge_queue?
      issue_event.message == "api_merge_queue_merge"
    end
  end
end
