# typed: true
# frozen_string_literal: true

class RepairIssuesIndexJob < Elastomer::RepairJob
  default_to_write_connection! # rubocop:todo GitHub/JobsDoNotDefaultToWriteConnection

  queue_as :index_bulk

  reconcile "issue",
    fields: %w[updated_at],
    limit: 750,
    accept: :parent_repo_is_searchable?,
    reject: :spammy?,
    include: [:repository, { assignments: :assignee }, :labels],
    conditions: "issues.has_pull_request = 0"
end
