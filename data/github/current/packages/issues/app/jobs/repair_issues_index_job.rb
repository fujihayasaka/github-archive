# typed: true
# frozen_string_literal: true

class RepairIssuesIndexJob < Elastomer::RepairJob
  queue_as :index_bulk

  reconcile "issue",
    fields: %w[updated_at],
    limit: 100,
    accept: :parent_repo_is_searchable?,
    reject: :spammy?,
    include: [:repository, { assignments: :assignee }, :labels],
    conditions: "issues.has_pull_request = 0",
    named_scopes: {
      user_created: -> (user_id) { Issue.where(user_id: user_id).where(pull_request_id: nil) },
      user_commented: -> (user_id) {
        Issue.joins(:comments)
          .where(issue_comments: { user_id: user_id })
          .where(pull_request_id: nil)
          .distinct
      },
    }
end
