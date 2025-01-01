# typed: true
# frozen_string_literal: true

class ChangeIssueTransfersKeysToBigInt < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesCollab)

  def up
    change_table :issue_transfers, bulk: true do |t|
      t.change :id, :bigint, unsigned: true, null: false, auto_increment: true
      t.change :old_repository_id, :bigint, unsigned: true, null: false
      t.change :old_issue_id, :bigint, unsigned: true, null: false
      t.change :old_issue_number, :bigint, unsigned: true, null: false
      t.change :new_repository_id, :bigint, unsigned: true, null: false
      t.change :new_issue_id, :bigint, unsigned: true, null: false
      t.change :actor_id, :bigint, unsigned: true, null: false
    end
  end

  def down
    change_table :issue_transfers, bulk: true do |t|
      t.change :id, :int, null: false, auto_increment: true
      t.change :old_repository_id, :int, null: false
      t.change :old_issue_id, :int, null: false
      t.change :old_issue_number, :int, null: false
      t.change :new_repository_id, :int, null: false
      t.change :new_issue_id, :int, null: false
      t.change :actor_id, :int, null: false
    end
  end
end
