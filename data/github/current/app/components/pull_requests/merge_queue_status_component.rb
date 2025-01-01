# typed: true
# frozen_string_literal: true

module PullRequests
  class MergeQueueStatusComponent < ApplicationComponent
    include StatusHelper

    # repository - the Repository the pull request would be merged into
    # pull_request - a PullRequest
    # is_merge_queue_enabled_for_pull_request - Boolean indicating whether a merge queue exists for the pull request's
    #                                           base branch
    def initialize(repository:, pull_request:, is_merge_queue_enabled_for_pull_request:)
      @repository = repository
      @pull_request = pull_request
      @is_merge_queue_enabled_for_pull_request = is_merge_queue_enabled_for_pull_request
    end

    private

    attr_reader :pull_request, :repository

    delegate :merge_queue, to: :pull_request

    def merge_button_scheme
      if ([:clean, :has_hooks].include?(merge_state.status)) && (!pull_request.draft?)
        :primary
      else
        :default
      end
    end

    # Return the PullRequest::MergeState for the current viewer
    memoize def merge_state
      pull_request.cached_merge_state(viewer: current_user)
    end

    def render?
      return false unless GitHub.merge_queues_enabled?
      @is_merge_queue_enabled_for_pull_request && pull_request.present? && repository.present?
    end

    memoize def time_estimate
      merge_queue&.next_entry_time_to_merge_in_seconds
    end

    def display_time_estimate
      return false if GitHub.flipper[:hide_merge_queue_time_estimate].enabled?(repository)
      time_estimate && !in_merge_queue?
    end

    def merge_when_ready_button_disabled?
      return true if pull_request.unknown_merge_state?(viewer: current_user)
      return true if pull_request.draft?
      return true if merge_state.blocked_by_invalid_merge_queue_config?

      false
    end

    def merge_queue_enforced_for_viewer?
      pull_request.protected_base_branch_merge_queue_enforced_for?(current_user)
    end

    memoize def viewer_can_add_to_merge_queue?
      # Don't need to pass `branch_name:` to check the pull request's base branch specifically since the given
      # `is_merge_queue_enabled_for_pull_request` view component parameter already checked that:
      repository.can_add_pull_requests_to_merge_queue?(current_user)
    end

    def viewer_can_add_to_merge_queue_solo?
      return false unless viewer_can_add_to_merge_queue?
      pull_request.can_add_to_merge_queue_solo?(current_user)
    end

    memoize def viewer_can_jump_merge_queue?
      pull_request.can_jump_merge_queue?(current_user)
    end

    def show_queue_and_force_solo_merge_button?
      viewer_can_add_to_merge_queue_solo? && requires_deployments_before_merging?
    end

    def show_jump_the_queue_button?
      viewer_can_jump_merge_queue? && requires_deployments_before_merging?
    end

    memoize def requires_deployments_before_merging?
      merge_queue.requires_deployments_before_merging?
    end

    memoize def in_merge_queue?
      pull_request.in_merge_queue?
    end
  end
end
