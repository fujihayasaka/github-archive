# typed: true
# frozen_string_literal: true

class PendingAutomaticInstallation < ApplicationRecord::Collab

  enum :status, [:pending, :installed, :failed]
  enum :reason, [:no_reason, :canceled]

  ALLOWED_TARGET_TYPES = %w(User Repository).freeze
  ALLOWED_TRIGGER_TYPES = %w(
    pending_dependabot_installation_requested
  ).freeze

  belongs_to :target, polymorphic: true

  before_validation :set_installed_at, if: :status_changed?

  validates :target_type, presence: true, inclusion: ALLOWED_TARGET_TYPES
  validates :trigger_type, presence: true, inclusion: ALLOWED_TRIGGER_TYPES

  def self.for(trigger_type)
    where(trigger_type: trigger_type, status: :pending)
  end

  def targeted_user
    target.is_a?(Repository) ? target.owner : target
  end

  def targeted_repository_ids
    target.is_a?(Repository) ? [target.id] : []
  end

  def stale?
    target.nil? || targeted_user.nil?
  end

  private

  def set_installed_at
    if status_was == "pending" && installed?
      self.installed_at = Time.now.in_time_zone
    end
  end
end
