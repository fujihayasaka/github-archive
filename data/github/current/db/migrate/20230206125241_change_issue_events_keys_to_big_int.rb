# typed: true
# frozen_string_literal: true

class ChangeIssueEventsKeysToBigInt < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def up
    change_table :issue_events, bulk: true do |t|
      t.change :issue_id, :bigint, unsigned: true, default: nil
      t.change :actor_id, :bigint, unsigned: true, default: nil
      t.change :repository_id, :bigint, unsigned: true, default: nil
      t.change :commit_repository_id, :bigint, unsigned: true, default: nil
      t.change :referencing_issue_id, :bigint, unsigned: true, default: nil
      t.change :performed_by_integration_id, :bigint, unsigned: true, default: nil
    end

    change_table :archived_issue_events, bulk: true do |t|
      t.change :issue_id, :bigint, unsigned: true, default: nil
      t.change :actor_id, :bigint, unsigned: true, default: nil
      t.change :repository_id, :bigint, unsigned: true, default: nil
      t.change :commit_repository_id, :bigint, unsigned: true, default: nil
      t.change :referencing_issue_id, :bigint, unsigned: true, default: nil
      t.change :performed_by_integration_id, :bigint, unsigned: true, default: nil
    end
  end

  def down
    change_table :issue_events, bulk: true do |t|
      t.change :issue_id, :int, unsigned: true, default: nil
      t.change :actor_id, :int, unsigned: true, default: nil
      t.change :repository_id, :int, unsigned: true, default: nil
      t.change :commit_repository_id, :int, unsigned: true, default: nil
      t.change :referencing_issue_id, :int, unsigned: true, default: nil
      t.change :performed_by_integration_id, :int, default: nil
    end

    change_table :archived_issue_events, bulk: true do |t|
      t.change :issue_id, :int, unsigned: true, default: nil
      t.change :actor_id, :int, unsigned: true, default: nil
      t.change :repository_id, :int, unsigned: true, default: nil
      t.change :commit_repository_id, :int, unsigned: true, default: nil
      t.change :referencing_issue_id, :int, unsigned: true, default: nil
      t.change :performed_by_integration_id, :int, default: nil
    end
  end
end
