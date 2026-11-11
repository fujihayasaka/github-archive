# typed: true
# frozen_string_literal: true

# rubocop:disable GitHub/DoNotAddUniqueIndexToExistingColumn

class UpdateUniqueIndexOnIssueEvents < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def up
    change_table :issue_events, bulk: true do |t|
      t.remove_index name: "idx_issue_events_event_source_id"
      t.index [:event, :source_id, :issue_id], name: "idx_issue_events_event_source_id_issue_id", unique: true
    end

    change_table :archived_issue_events, bulk: true do |t|
      t.remove_index name: "idx_issue_events_event_source_id"
      t.index [:event, :source_id, :issue_id], name: "idx_issue_events_event_source_id_issue_id", unique: true
    end
  end

  def down
    change_table :issue_events, bulk: true do |t|
      t.remove_index name: "idx_issue_events_event_source_id"
      t.index [:event, :source_id], unique: true, name: "idx_issue_events_event_source_id"
    end

    change_table :archived_issue_events, bulk: true do |t|
      t.remove_index name: "idx_issue_events_event_source_id"
      t.index [:event, :source_id], unique: true, name: "idx_issue_events_event_source_id"
    end
  end
end
