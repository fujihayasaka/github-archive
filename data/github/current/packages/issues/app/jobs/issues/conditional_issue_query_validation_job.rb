# typed: true
# frozen_string_literal: true

module Issues
  class ConditionalIssueQueryValidationJob < ApplicationJob
    queue_as :conditional_issue_query_validation

    retry_on_dirty_exit

    QUERY_CLASSES = [::Search::Queries::IssueQuery, ::Search::Queries::ConditionalIssueQuery].freeze

    def perform(
      allow_insecure_user_to_server_app_query:,
      current_user:,
      user_session:,
      repo_id:,
      remote_ip:,
      current_installation:,
      aggregations:,
      phrase:,
      highlight:,
      normalizer:,
      source_fields:,
      context:,
      catalog_service:
    )
      return if GitHub.enterprise?
      # for each class in QUERY_CLASSES, initialize and capture the output, then compare the outputs

      GitHub.logger.info("ConditionalIssueQueryValidationJob Results", {
        "gh.enduser.login": current_user.display_login,
        "gh.issues_advanced_search.query": phrase,
      })

      # log matches and mismatches to splunk
    end
  end
end
