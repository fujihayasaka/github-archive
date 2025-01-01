# typed: true
# frozen_string_literal: true

class ChangeDeletedIssuesKeysToBigInt < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesCollab)

  def up
    change_table :deleted_issues, bulk: true do |t|
      t.change :id, :bigint, unsigned: true, null: false, auto_increment: true
      t.change :repository_id, :bigint, unsigned: true, null: false
      t.change :deleted_by_id, :bigint, unsigned: true, null: false
      t.change :old_issue_id, :bigint, unsigned: true, null: false
    end
  end

  def down
    change_table :deleted_issues, bulk: true do |t|
      t.change :id, :int, null: false, auto_increment: true
      t.change :repository_id, :int, null: false
      t.change :deleted_by_id, :int, null: false
      t.change :old_issue_id, :int, null: false
    end
  end
end
