# typed: true
# frozen_string_literal: true

class Codespaces::UpcomingRetentionNotificationJob < CodespacesJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
  schedule interval: 1.hour, condition: -> { !GitHub.enterprise? }

  # +------------------+---------------------------+
  # | Retention Period |          Notify           |
  # +------------------+---------------------------+
  # | 8-30 days        | 7 days prior              |
  # | 5-8 days         | 4 days prior              |
  # | 1-4 days         | 1 day (24 hours)          |
  # | < 1 day          | no notification required. |
  # +------------------+---------------------------+
  def perform
    expiring_7 = Set.new(codespaces(expiring_in: 7.days).where("retention_period_minutes >= ?", 8.days.in_minutes))
    expiring_7.reject! { |codespace| already_notified?(codespace) }
    GitHub.dogstats.count("codespaces.retention_notification", expiring_7.size, tags: ["period:7d"])

    expiring_4 = Set.new(codespaces(expiring_in: 4.days).
      where("retention_period_minutes >= ? AND retention_period_minutes < ?", 5.days.in_minutes, 8.days.in_minutes))
    expiring_4.reject! { |codespace| already_notified?(codespace) }
    GitHub.dogstats.count("codespaces.retention_notification", expiring_4.size, tags: ["period:4d"])

    expiring_1 = Set.new(codespaces(expiring_in: 1.day))
    expiring_1.reject! { |codespace| already_notified?(codespace) }
    GitHub.dogstats.count("codespaces.retention_notification", expiring_1.size, tags: ["period:1d"])

    owners = (expiring_7 | expiring_4 | expiring_1).map!(&:owner_id)
    GitHub.dogstats.count("codespaces.retention_notification.owners", owners.size, tags: ["period:1d"])

    User.where(id: owners).find_in_batches do |users|
      flagged_users = Set.new(users.select { |user| user.feature_flag_enabled_or_raise?(:codespaces_expiry_notification_setting) }) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      Configurable.preload_configuration(flagged_users)

      users.each do |user|
        if flagged_users.include?(user)
          next unless user.codespaces_expiry_notification_enabled?
        end
        Codespaces::NotifyOwnerOfExpiringCodespacesJob.perform_later(user.id)
      end
    end
  end

  private

  def codespaces(expiring_in:)
    Codespace.
      provisioned.
      only_codespaces.
      select(:id, :owner_id).
      where("retention_expires_at BETWEEN ? AND ?", expiring_in.from_now - 1.5.hours, expiring_in.from_now + 1.5.hours)
  end

  def already_notified?(codespace)
    key = "codespaces:retention_notified:#{codespace.id}"
    Codespaces::Kv.store.get(key).value { nil }.present?
  end
end
