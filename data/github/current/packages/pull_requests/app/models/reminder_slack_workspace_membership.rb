# typed: true
# frozen_string_literal: true

class ReminderSlackWorkspaceMembership < ApplicationRecord::Collab
  belongs_to :user
  # rubocop:todo Rails/InverseOf
  belongs_to :slack_workspace, class_name: "ReminderClientWorkspace", foreign_key: "reminder_slack_workspace_id"
  # rubocop:enable Rails/InverseOf

  validates :user_id, uniqueness: { scope: [:reminder_slack_workspace_id] }

  def self.create_or_update_membership(user_id:, reminder_slack_workspace_id:)
    self.connection.insert(Arel.sql(<<-SQL, user_id: user_id, reminder_slack_workspace_id: reminder_slack_workspace_id))
      INSERT INTO reminder_slack_workspace_memberships (user_id, reminder_slack_workspace_id, created_at, updated_at)
      VALUES (:user_id, :reminder_slack_workspace_id, NOW(), NOW())
      ON DUPLICATE KEY UPDATE
        updated_at = NOW()
    SQL
    find_by!(user_id: user_id, reminder_slack_workspace_id: reminder_slack_workspace_id)
  end
end
