# typed: true
# frozen_string_literal: true

class AddTotalCountColumnsToIssueDependencyLists < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    change_table :issue_dependency_lists, bulk: true do |t|
      t.column :total_blocking, :integer, unsigned: true, null: false, default: 0
      t.column :total_blocked_by, :integer, unsigned: true, null: false, default: 0
    end
  end
end
