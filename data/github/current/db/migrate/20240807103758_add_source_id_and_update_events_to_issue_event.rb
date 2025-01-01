# rubocop:disable GitHub/DoNotAddUniqueIndexToExistingColumn

# typed: true
# frozen_string_literal: true

class AddSourceIdAndUpdateEventsToIssueEvent < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def up
    change_table(:issue_events, bulk: :true) do |t|
      t.change :event, "enum('abandoned_review','added_to_merge_queue','added_to_project','assigned','auto_merge_disabled','auto_merge_enabled','auto_rebase_enabled','auto_squash_enabled','automatic_base_change_failed','automatic_base_change_succeeded','base_ref_changed','base_ref_deleted','base_ref_force_pushed','closed','comment_deleted','connected','convert_to_draft','converted_note_to_issue','converted_to_discussion','demilestoned','deployed','deployment_environment_changed','disconnected','head_ref_cleaned','head_ref_deleted','head_ref_force_pushed','head_ref_restored','labeled','locked','marked_as_duplicate','mentioned','merged','milestoned','moved_columns_in_project','pinned','ready_for_review','referenced','removed_from_merge_queue','removed_from_project','renamed','reopened','reverted','review_abandoned','review_dismissed','review_request_removed','review_requested','review_unrequested','signoff','signoff_canceled','slash_command_executed','subscribed','transferred','unassigned','unlabeled','unlocked','unmarked_as_duplicate','unpinned','unsubscribed','user_blocked', 'converted_from_draft','added_to_project_v2','removed_from_project_v2','project_v2_item_status_changed')", null: false
      t.string :source_id, limit: 36
      t.index [:event, :source_id], name: "idx_issue_events_event_source_id", unique: true
    end

    change_table(:archived_issue_events, bulk: :true) do |t|
      t.change :event, "enum('abandoned_review','added_to_merge_queue','added_to_project','assigned','auto_merge_disabled','auto_merge_enabled','auto_rebase_enabled','auto_squash_enabled','automatic_base_change_failed','automatic_base_change_succeeded','base_ref_changed','base_ref_deleted','base_ref_force_pushed','closed','comment_deleted','connected','convert_to_draft','converted_note_to_issue','converted_to_discussion','demilestoned','deployed','deployment_environment_changed','disconnected','head_ref_cleaned','head_ref_deleted','head_ref_force_pushed','head_ref_restored','labeled','locked','marked_as_duplicate','mentioned','merged','milestoned','moved_columns_in_project','pinned','ready_for_review','referenced','removed_from_merge_queue','removed_from_project','renamed','reopened','reverted','review_abandoned','review_dismissed','review_request_removed','review_requested','review_unrequested','signoff','signoff_canceled','slash_command_executed','subscribed','transferred','unassigned','unlabeled','unlocked','unmarked_as_duplicate','unpinned','unsubscribed','user_blocked', 'converted_from_draft','added_to_project_v2','removed_from_project_v2','project_v2_item_status_changed')", null: false
      t.string :source_id, limit: 36
      t.index [:event, :source_id], name: "idx_issue_events_event_source_id", unique: true
    end
  end

  def down
    change_table(:issue_events, bulk: :true) do |t|
      t.remove_index name: "idx_issue_events_event_source_id"
      t.remove :source_id
      t.change :event, "enum('abandoned_review','added_to_merge_queue','added_to_project','assigned','auto_merge_disabled','auto_merge_enabled','auto_rebase_enabled','auto_squash_enabled','automatic_base_change_failed','automatic_base_change_succeeded','base_ref_changed','base_ref_deleted','base_ref_force_pushed','closed','comment_deleted','connected','convert_to_draft','converted_note_to_issue','converted_to_discussion','demilestoned','deployed','deployment_environment_changed','disconnected','head_ref_cleaned','head_ref_deleted','head_ref_force_pushed','head_ref_restored','labeled','locked','marked_as_duplicate','mentioned','merged','milestoned','moved_columns_in_project','pinned','ready_for_review','referenced','removed_from_merge_queue','removed_from_project','renamed','reopened','reverted','review_abandoned','review_dismissed','review_request_removed','review_requested','review_unrequested','signoff','signoff_canceled','slash_command_executed','subscribed','transferred','unassigned','unlabeled','unlocked','unmarked_as_duplicate','unpinned','unsubscribed','user_blocked')", null: false
    end

    change_table(:archived_issue_events, bulk: :true) do |t|
      t.remove_index name: "idx_issue_events_event_source_id"
      t.remove :source_id
      t.change :event, "enum('abandoned_review','added_to_merge_queue','added_to_project','assigned','auto_merge_disabled','auto_merge_enabled','auto_rebase_enabled','auto_squash_enabled','automatic_base_change_failed','automatic_base_change_succeeded','base_ref_changed','base_ref_deleted','base_ref_force_pushed','closed','comment_deleted','connected','convert_to_draft','converted_note_to_issue','converted_to_discussion','demilestoned','deployed','deployment_environment_changed','disconnected','head_ref_cleaned','head_ref_deleted','head_ref_force_pushed','head_ref_restored','labeled','locked','marked_as_duplicate','mentioned','merged','milestoned','moved_columns_in_project','pinned','ready_for_review','referenced','removed_from_merge_queue','removed_from_project','renamed','reopened','reverted','review_abandoned','review_dismissed','review_request_removed','review_requested','review_unrequested','signoff','signoff_canceled','slash_command_executed','subscribed','transferred','unassigned','unlabeled','unlocked','unmarked_as_duplicate','unpinned','unsubscribed','user_blocked')", null: false
    end
  end
end
