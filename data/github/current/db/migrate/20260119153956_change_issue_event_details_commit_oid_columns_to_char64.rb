# typed: true
# frozen_string_literal: true

class ChangeIssueEventDetailsCommitOidColumnsToChar64 < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    reversible do |dir|
      change_table :issue_event_details, bulk: true do |t|
        dir.up do
          t.change :before_commit_oid, "char(64)", null: true
          t.change :after_commit_oid, "char(64)", null: true
        end

        dir.down do
          t.change :before_commit_oid, "char(40)", null: true
          t.change :after_commit_oid, "char(40)", null: true
        end
      end

      change_table :archived_issue_event_details, bulk: true do |t|
        dir.up do
          t.change :before_commit_oid, "char(64)", null: true
          t.change :after_commit_oid, "char(64)", null: true
        end

        dir.down do
          t.change :before_commit_oid, "char(40)", null: true
          t.change :after_commit_oid, "char(40)", null: true
        end
      end
    end
  end
end
