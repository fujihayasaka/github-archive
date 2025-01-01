# typed: true
# frozen_string_literal: true

class RemovePrivateIssueTypesFromEventDetails < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def up
    change_table :issue_event_details, bulk: :true do |t|
      t.remove :issue_type_private
      t.remove :prev_issue_type_private
    end

    # Archive Tables
    change_table :archived_issue_event_details, bulk: :true do |t|
      t.remove :issue_type_private
      t.remove :prev_issue_type_private
    end
  end

  def down
    change_table :issue_event_details, bulk: :true do |t|
      t.column :issue_type_private, :boolean, default: false, null: false
      t.column :prev_issue_type_private, :boolean, default: false, null: false
    end

    # Archive Tables
    change_table :archived_issue_event_details, bulk: :true do |t|
      t.column :issue_type_private, :boolean, default: false, null: false
      t.column :prev_issue_type_private, :boolean, default: false, null: false
    end
  end
end
