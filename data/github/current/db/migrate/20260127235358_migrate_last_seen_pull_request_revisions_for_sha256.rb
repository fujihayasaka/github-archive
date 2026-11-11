# typed: true
# frozen_string_literal: true

# rubocop:disable GitHub/ExistingIdColumnsMustBeBigint

class MigrateLastSeenPullRequestRevisionsForSha256 < ActiveRecord::Migration[8.2]
  use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def up
    change_table :last_seen_pull_request_revisions, bulk: true do |t|
      t.change :last_revision, "varbinary(32)", null: false
    end
  end

  def down
    change_table :last_seen_pull_request_revisions, bulk: true do |t|
      t.change :last_revision, "varbinary(20)", null: false
    end
  end
end
