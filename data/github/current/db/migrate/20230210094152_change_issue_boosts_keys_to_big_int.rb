# typed: true
# frozen_string_literal: true

class ChangeIssueBoostsKeysToBigInt < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesCollab)

  def up
    change_table :issue_boosts, bulk: true do |t|
      t.change :id, :bigint, unsigned: true, null: false, auto_increment: true
      t.change :user_id, :bigint, unsigned: true, null: false
      t.change :issue_id, :bigint, unsigned: true, null: false
    end
  end

  def down
    change_table :issue_boosts, bulk: true do |t|
      t.change :id, :int, null: false, auto_increment: true
      t.change :user_id, :int, null: false
      t.change :issue_id, :int, null: false
    end
  end
end
