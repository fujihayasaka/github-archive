# typed: true
# frozen_string_literal: true

class AddProjectidStatusPreviousStatusToIssueEventDetails < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def up
    change_table(:issue_event_details, bulk: true) do |t|
      t.bigint :project_id, unsigned: true
      t.text :project_previous_status
      t.text :project_status
    end

    change_table(:archived_issue_event_details, bulk: true) do |t|
      t.bigint :project_id, unsigned: true
      t.text :project_previous_status
      t.text :project_status
    end
  end

  def down
    change_table(:issue_event_details, bulk: true) do |t|
      t.remove :project_status
      t.remove :project_previous_status
      t.remove :project_id
    end

    change_table(:archived_issue_event_details, bulk: true) do |t|
      t.remove :project_status
      t.remove :project_previous_status
      t.remove :project_id
    end
  end
end
