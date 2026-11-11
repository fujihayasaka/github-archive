# typed: true
# frozen_string_literal: true

class ChangeIssueCommentsKeysToBigInt < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def up
    change_table :issue_comments, bulk: true do |t|
      t.change :id, :bigint, unsigned: true, null: false, auto_increment: true
      t.change :issue_id, :bigint, unsigned: true, null: false
      t.change :user_id, :bigint, unsigned: true, default: nil
      t.change :repository_id, :bigint, unsigned: true, null: false
      t.change :performed_by_integration_id, :bigint, unsigned: true, default: nil
    end

    change_table :archived_issue_comments, bulk: true do |t|
      t.change :id, :bigint, unsigned: true, null: false, auto_increment: true
      t.change :issue_id, :bigint, unsigned: true, null: false
      t.change :user_id, :bigint, unsigned: true, default: nil
      t.change :repository_id, :bigint, unsigned: true, null: false
      t.change :performed_by_integration_id, :bigint, unsigned: true, default: nil
    end
  end

  def down
    change_table :issue_comments, bulk: true do |t|
      t.change :id, :int, null: false, auto_increment: true
      t.change :issue_id, :int, null: false
      t.change :user_id, :int, default: nil
      t.change :repository_id, :int, null: false
      t.change :performed_by_integration_id, :int, default: nil
    end

    change_table :archived_issue_comments, bulk: true do |t|
      t.change :id, :int, null: false, auto_increment: true
      t.change :issue_id, :int, null: false
      t.change :user_id, :int, default: nil
      t.change :repository_id, :int, null: false
      t.change :performed_by_integration_id, :int, default: nil
    end
  end
end
