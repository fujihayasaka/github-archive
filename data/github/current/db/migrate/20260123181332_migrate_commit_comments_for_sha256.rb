# typed: true
# frozen_string_literal: true

# rubocop:disable GitHub/ExistingIdColumnsMustBeBigint

class MigrateCommitCommentsForSha256 < ActiveRecord::Migration[8.2]
  use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def up
    change_table :commit_comments, bulk: true do |t|
      t.change :commit_id, :string, limit: 64, null: false
    end

    change_table :archived_commit_comments, bulk: true do |t|
      t.change :commit_id, :string, limit: 64, null: false
    end
  end

  def down
    change_table :commit_comments, bulk: true do |t|
      t.change :commit_id, :string, limit: 40, null: false
    end

    change_table :archived_commit_comments, bulk: true do |t|
      t.change :commit_id, :string, limit: 40, null: false
    end
  end
end
