# typed: true
# frozen_string_literal: true

class ChangeIssueLinksKeysToBigInt < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def up
    change_table :issue_links, bulk: true do |t|
      t.change :id, :bigint, unsigned: true, null: false, auto_increment: true
      t.change :source_issue_id, :bigint, unsigned: true, null: false
      t.change :target_issue_id, :bigint, unsigned: true, null: false
      t.change :actor_id, :bigint, unsigned: true, null: false
      t.change :source_repository_id, :bigint, unsigned: true, null: false
      t.change :target_repository_id, :bigint, unsigned: true, null: false
    end
  end

  def down
    change_table :issue_links, bulk: true do |t|
      t.change :id, :int, null: false, auto_increment: true
      t.change :source_issue_id, :int, null: false
      t.change :target_issue_id, :int, null: false
      t.change :actor_id, :int, null: false
      t.change :source_repository_id, :int, null: false
      t.change :target_repository_id, :int, null: false
    end
  end
end
