# typed: true
# frozen_string_literal: true

class ChangeCloseIssueReferencesKeysToBigInt < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesCollab)

  def up
    change_table :close_issue_references, bulk: true do |t|
      t.change :id, :bigint, unsigned: true, null: false, auto_increment: true
      t.change :pull_request_id, :bigint, unsigned: true, null: false
      t.change :issue_id, :bigint, unsigned: true, null: false
      t.change :pull_request_author_id, :bigint, unsigned: true, null: false
      t.change :issue_repository_id, :bigint, unsigned: true, null: false
      t.change :actor_id, :bigint, unsigned: true, default: nil
    end
  end

  def down
    change_table :close_issue_references, bulk: true do |t|
      t.change :id, :int, null: false, auto_increment: true
      t.change :pull_request_id, :int, null: false
      t.change :issue_id, :int, null: false
      t.change :pull_request_author_id, :int, null: false
      t.change :issue_repository_id, :int, null: false
      t.change :actor_id, :int, default: nil
    end
  end
end
