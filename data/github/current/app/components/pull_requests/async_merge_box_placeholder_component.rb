# typed: true
# frozen_string_literal: true

module PullRequests
  class AsyncMergeBoxPlaceholderComponent < ApplicationComponent

    attr_reader :pull_request, :gate_requests
    include MergeboxHelper

    def initialize(pull_request:, gate_requests:)
      @pull_request = pull_request
      @gate_requests = gate_requests
    end

    def show_merge_placeholder?
      pull_request.open? && !pull_request.merged?
    end

    def show_opt_in_opt_out_react_feature_preview?(current_user:)
      # Don't auto return if user has admin bypass override of merge box GA
      return false if current_user&.feature_enabled?(:new_merge_box_ga) && !current_user&.feature_enabled?(:new_merge_box_ga_bypass_override)

      if pull_request.merged? || pull_request.closed?
        return true if pull_request.head_ref_restorable_by?(current_user)

        pull_request.head_ref_deleteable_by?(current_user) && pull_request.head_ref_deleteable_after_updating_dependents?(current_user)
      else
        true
      end
    end

    def src_path
      pull_request_merging_partial_path(user_id: pull_request.repository.owner, repository: pull_request.repository, id: pull_request.number)
    end

    def head_ref_tree_path
      link_to(pull_request.display_head_ref_name, tree_path("", pull_request.display_head_ref_name, pull_request.head_repository), class: "text-emphasized")
    end

    def repo_path
      link_to(pull_request.head_repository.name_with_display_owner, repository_path(pull_request.head_repository), class: "text-emphasized")
    end

    def pull_request_base_page_data_path
      pull_request_path(pull_request)
    end

    def new_mergebox_feature_enabled?
      new_mergebox_feature_enabled_for_user?(current_user, params)
    end

    def new_mergebox_feature_flag_enabled?
      new_mergebox_feature_flag_enabled_for_user?(current_user)
    end

    def default_merge_method(current_user:)
      default_merge_method_for_user(pull_request, current_user)
    end

    def new_mergebox_feedback_link
      "https://gh.io/new-merge-box-feedback"
    end

    def alive_channels
      PullRequests::PageData::MergeBox::PullRequestPayload::MergeBoxAliveChannels.new(
        stateChannel: GitHub::WebSocket::Channels.signed_pull_request_state(pull_request),
        deployedChannel: GitHub::WebSocket::Channels.signed_pull_request_deployed(pull_request),
        reviewStateChannel: GitHub::WebSocket::Channels.signed_pull_request_review_state(pull_request),
        workflowsChannel: GitHub::WebSocket::Channels.signed_pull_request_workflow_run_state(pull_request),
        mergeQueueChannel:  GitHub::WebSocket::Channels.signed_pull_request_merge_queue_entry_state(pull_request),
        headRefChannel: pull_request.head_repository ? GitHub::WebSocket::Channels.signed_branch(pull_request.head_repository, pull_request.display_head_ref_name) : nil,
        baseRefChannel: GitHub::WebSocket::Channels.signed_branch(pull_request.base_repository, pull_request.display_base_ref_name),
        gitMergeStateChannel: GitHub::WebSocket::Channels.signed_pull_request_git_merge_state(pull_request),
        pullRequestChannel: GitHub::WebSocket::Channels.signed_pull_request(pull_request)
      )
    end
  end
end
