# typed: true
# frozen_string_literal: true

class RemovePrivateFromIssueTypes < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def up
    change_table :issue_types, bulk: true do |t|
      t.remove :private
    end
  end

  def down
    change_table :issue_types, bulk: true do |t|
      t.boolean :private, default: false, null: false
    end
  end
end
