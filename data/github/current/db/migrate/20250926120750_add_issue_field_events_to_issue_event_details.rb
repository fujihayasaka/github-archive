# typed: true
# frozen_string_literal: true

class AddIssueFieldEventsToIssueEventDetails < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    change_table :issue_event_details, bulk: :true do |t|
      t.column :issue_field_id, :bigint, unsigned: true
      t.column :issue_field_name, :string, limit: 255, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci"
      t.column :issue_field_data_type, :integer, limit: 1
      t.column :issue_field_value, :json
      t.column :prev_issue_field_value, :json
      t.column :issue_field_value_color, :integer
      t.column :prev_issue_field_value_color, :integer
    end

    change_table :archived_issue_event_details, bulk: :true do |t|
      t.column :issue_field_id, :bigint, unsigned: true
      t.column :issue_field_name, :string, limit: 255, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci"
      t.column :issue_field_data_type, :integer, limit: 1
      t.column :issue_field_value, :json
      t.column :prev_issue_field_value, :json
      t.column :issue_field_value_color, :integer
      t.column :prev_issue_field_value_color, :integer
    end
  end
end
