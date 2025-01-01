# typed: true
# frozen_string_literal: true

module PullRequests
  class AsyncMergeBoxPlaceholderComponent < ApplicationComponent

    attr_reader :pull_request, :gate_requests
    include ReactHelper, MergeboxHelper

    def initialize(pull_request:, gate_requests:)
      @pull_request = pull_request
      @gate_requests = gate_requests
    end

    def show_merge_placeholder?
      pull_request.open? && !pull_request.merged?
    end

    def show_opt_in_opt_out_react_feature_preview?(current_user:)
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

    def set_react_tag
      GitHub.dogstats.increment(
        "pull_request.merge_box_view",
        tags: ["version:react", "staff:#{is_staff?}"]
      )
    end

    def set_rails_tag
      GitHub.dogstats.increment(
        "pull_request.merge_box_view",
        tags: ["version:rails", "staff:#{is_staff?}"]
      )
    end

    def is_staff?
      current_user&.employee? ? true : false
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
  end
end
