# typed: true
# frozen_string_literal: true

class AddIssueTypeEventsToIssueeventdetails < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    change_table :issue_event_details, bulk: :true do |t|
      t.column :issue_type_id, :bigint, unsigned: true
      t.column :issue_type_name, :string, limit: 64, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci"
      t.column :issue_type_color, :string, limit: 6
      t.column :issue_type_private, :boolean, default: false, null: false
      t.column :prev_issue_type_id, :bigint, unsigned: true
      t.column :prev_issue_type_name, :string, limit: 64, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci"
      t.column :prev_issue_type_color, :string, limit: 6
      t.column :prev_issue_type_private, :boolean, default: false, null: false
    end

    # Archive Tables
    change_table :archived_issue_event_details, bulk: :true do |t|
      t.column :issue_type_id, :bigint, unsigned: true
      t.column :issue_type_name, :string, limit: 64, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci"
      t.column :issue_type_color, :string, limit: 6
      t.column :issue_type_private, :boolean, default: false, null: false
      t.column :prev_issue_type_id, :bigint, unsigned: true
      t.column :prev_issue_type_name, :string, limit: 64, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci"
      t.column :prev_issue_type_color, :string, limit: 6
      t.column :prev_issue_type_private, :boolean, default: false, null: false
    end
  end
end
