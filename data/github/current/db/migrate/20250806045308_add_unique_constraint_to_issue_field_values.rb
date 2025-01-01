# typed: true
# frozen_string_literal: true

class AddUniqueConstraintToIssueFieldValues < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    change_table :issue_field_values, bulk: true do |t|
      # Remove the existing non-unique indices to avoid redundancy with our new unique constraint.
      # The unique index on (repository_id, issue_id, issue_field_id) will handle all queries that the 3-column
      # index was serving, including lookups with data_type due to MySQL's leftmost prefix rule.
      t.remove_index [:issue_id, :issue_field_id, :data_type], name: "index_issue_field_values_on_issue_id_issue_field_id_data_type"
      t.remove_index [:repository_id, :issue_id], name: "index_issue_field_values_on_repository_id_issue_id"
      # Add unique constraint to prevent duplicate issue field values per issue and repository
      # This prevents race conditions where multiple requests try to create
      # the same issue field value simultaneously. Including repository_id makes the constraint
      # more explicit since uniqueness is per repo, and removes confusion around Vitess sharding the issues by repo_id.
      # Reason to disable the linting below: This is a new table and not used much and we've verified that there is no duplicated data that will cause our migration to fail.
      # Therefore, we can safely add the unique index without worrying about existing duplicates.
      # rubocop:disable GitHub/DoNotAddUniqueIndexToExistingColumn
      t.index [:repository_id, :issue_id, :issue_field_id], unique: true, name: "index_issue_field_values_on_repository_issue_issue_field_unique"
      # rubocop:enable GitHub/DoNotAddUniqueIndexToExistingColumn
    end
  end
end
