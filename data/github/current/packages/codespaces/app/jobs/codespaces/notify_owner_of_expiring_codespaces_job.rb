# typed: true
# frozen_string_literal: true

class Codespaces::NotifyOwnerOfExpiringCodespacesJob < CodespacesJob
  retry_on_dirty_exit

  def perform(owner_id)
    expiring_codespaces = Codespace.
      provisioned.
      only_codespaces.
      where(owner_id: owner_id).
      where("retention_expires_at BETWEEN ? AND ?", 7.days.from_now - 1.5.hours, 7.days.from_now + 24.hours).
      where("retention_period_minutes >= ?", 8.days.in_minutes).
      order(retention_expires_at: :asc)

    expiring_codespaces += Codespace.
      provisioned.
      only_codespaces.
      where(owner_id: owner_id).
      where("retention_expires_at BETWEEN ? AND ?", 4.days.from_now - 1.5.hours, 4.days.from_now + 24.hours).
      where("retention_period_minutes >= ? AND retention_period_minutes < ?", 5.days.in_minutes, 8.days.in_minutes).
      order(retention_expires_at: :asc)

    expiring_codespaces += Codespace.
      provisioned.
      only_codespaces.
      where(owner_id: owner_id).
      where("retention_expires_at BETWEEN ? AND ?", 23.hours.from_now, 48.hours.from_now).
      order(retention_expires_at: :asc)

    require_notification = expiring_codespaces.to_a.reject do |codespace|
      key = "codespaces:retention_notified:#{codespace.id}"
      Codespaces::Kv.store.get(key).value { nil }.present?
    end

    if require_notification.any?
      GitHub.dogstats.count("codespaces.retention_notification_batch_email", require_notification.size)
      GitHub.logger.info(
        "sending retention period email",
        "gh.catalog_service" => "github/codespaces",
        "gh.codespaces.owner_id" => owner_id,
        "gh.codespaces.ids" => require_notification.map(&:id),
      )

      CodespacesRetentionMailer.retention_warning_batch(require_notification).deliver_later
      ActiveRecord::Base.connected_to(role: :writing) do
        require_notification.each do |codespace|
          key = "codespaces:retention_notified:#{codespace.id}"
          Codespaces::Kv.store.set(key, Time.now.iso8601, expires: 30.days.from_now)
        end
      end
    else
      GitHub.logger.info(
        "skipping retention period email due to already being sent",
        "gh.catalog_service" => "github/codespaces",
        "gh.codespaces.owner_id" => owner_id,
      )
    end
  end
end
