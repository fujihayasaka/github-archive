# typed: true
# frozen_string_literal: true

class AddTriggerSourceUrlAndTypeToIssueEventDetails < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    change_table :issue_event_details, bulk: true do |t|
      t.string :trigger_source_type, null: true
      t.text :trigger_source_url, null: true
    end

    change_table :archived_issue_event_details, bulk: true do |t|
      t.string :trigger_source_type, null: true
      t.text :trigger_source_url, null: true
    end
  end
end
