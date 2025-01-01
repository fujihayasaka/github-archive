# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class IssueAndPullRequestFilters < Platform::Inputs::Base
      description "Ways in which to filter lists of pull requests."

      visibility :under_development

      argument :assignee, String, "The assignee by which the list is filtered.", required: false
      argument :author, String, "The author by which the list is filtered.", required: false
      argument :label, String, "The label name by which the list is filtered.", required: false
      argument :mentions, String, "The mentioned login by which the list is filtered.", required: false
      argument :milestone, String, "The label name by which the list is filtered.", required: false
      argument :repository, [String], "The name with owner of the repository to filter issues and pull requests by.", required: false
      argument :reviewed_by, String, "The login of the reviewer by whom the pull requests are filtered.", required: false
      argument :review_requested, String, "The login of the requested reviewer by whom the pull requests are filtered.", required: false
      argument :review_state, Enums::PullRequestReviewStateFilter, "The review state by which the pull requests are filtered.", required: false
      argument :state, Enums::PullRequestState, "The state by which the list is filtered.", required: false
      argument :type, Enums::IssueOrPullRequestType, "The type by which to filter the list to.", required: false
    end
  end
end
