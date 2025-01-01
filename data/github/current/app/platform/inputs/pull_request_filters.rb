# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class PullRequestFilters < Platform::Inputs::Base
      description "Ways in which to filter lists of pull requests."
      feature_flag :gh_cli

      argument :assignee, String, "The assignee by which the pull requests are filtered.", required: false
      argument :author, String, "The author by which the pull requests are filtered.", required: false
      argument :base_ref_name, String, "The name of the base branch by which the pull requests are filtered", required: false
      argument :labels, [String], "The label names by which the pull requests are filtered.", required: false
      argument :mentions, String, "The mentioned login by which the pull requests are filtered.", required: false
      argument :milestone, String, "The milestone by which the pull requests are filtered.", required: false
      argument :reviewed_by, String, "The login of the reviewer by whom the pull requests are filtered.", required: false
      argument :review_requested, String, "The login of the requested reviewer by whom the pull requests are filtered.", required: false
      argument :review_state, Enums::PullRequestReviewStateFilter, "The review state by which the pull requests are filtered.", required: false
      argument :state, Enums::PullRequestState, "The state by which the pull requests are filtered.", required: false
    end
  end
end
