# typed: true
# frozen_string_literal: true

class ReminderClientWorkspace < ApplicationRecord::Collab # rubocop:todo GitHub/DatabaseModelsShouldHaveTests
  self.table_name = "reminder_slack_workspaces"

  belongs_to :remindable, polymorphic: true

  # rubocop:todo Rails/InverseOf
  has_many :reminders, foreign_key: "reminder_slack_workspace_id", class_name: "Reminder", dependent: :destroy
  has_many :personal_reminders, foreign_key: "reminder_slack_workspace_id", class_name: "PersonalReminder", dependent: :destroy
  has_many :reminder_slack_workspace_memberships, foreign_key: "reminder_slack_workspace_id", autosave: true, dependent: :destroy
  # rubocop:enable Rails/InverseOf

  validates_presence_of(:name, :slack_id, :remindable)
  validates :slack_id, length: { maximum: 48 }, uniqueness: { scope: [:remindable_type, :remindable_id], case_sensitive: false }

  scope :for_remindable, -> (remindable) { where(remindable: remindable) }

  attribute :name, StringFromBinary.new

  def member?(user)
    reminder_slack_workspace_memberships.where(user: user).exists?
  end

  def self.create_or_update_workspace_for_type(name:, remindable:, client_id:, type:)
    # Some remindable classes use single table inheritance (Organization, User, etc.)
    # Storing their inherited class name rather than base class name in the polymorphic
    # type field would work fine, but would be inconsistent with ActiveRecord conventions.
    self.connection.insert(Arel.sql(<<-SQL, name: name, remindable_type: remindable.class.base_class, remindable_id: remindable.id, client_id: client_id, type: type))
      INSERT INTO reminder_slack_workspaces (remindable_type, remindable_id, slack_id, name, type, created_at, updated_at)
      VALUES (:remindable_type, :remindable_id, :client_id, :name, :type, NOW(), NOW())
      ON DUPLICATE KEY UPDATE
        name = :name,
        updated_at = NOW()
    SQL
    find_by!(remindable: remindable, slack_id: client_id, type: type)
  end
end
