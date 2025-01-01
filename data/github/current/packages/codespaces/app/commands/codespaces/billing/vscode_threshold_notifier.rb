# typed: true
# frozen_string_literal: true
class Codespaces::Billing::VscodeThresholdNotifier < Codespaces::Command
  include GitHub::Memoizer

  attr_reader :codespace, :billable_owner

  def initialize(codespace:, billable_owner:)
    @codespace = codespace
    @billable_owner = billable_owner
  end

  def perform
    # can't receive a toast notification in VS Code unless the codespace is running
    return unless codespace&.available?

    # For the same codespace, do not need to check multiple times in 30 seconds if this is run multiple times
    notif_check_cache_key = "#{self.class}:#{codespace.guid}"
    return if Codespaces::Kv.store.exists(notif_check_cache_key).value { false }

    entitlements_message, thresholds = EntitlementsThresholdNotification.notification_to_send(billable_owner: billable_owner)

    ActiveRecord::Base.connected_to(role: :writing) do
      Codespaces::Kv.store.set(notif_check_cache_key, Time.now.iso8601, expires: 30.seconds.from_now)
    end

    # If nil, no notification is needed
    return unless entitlements_message

    # For the same codespace, do not send the same threshold notification twice in the same billing period
    cache_key = "#{self.class}:#{codespace.guid}:#{thresholds.map { |k, v| "#{k}:#{v}" }.join(",") }"
    return if Codespaces::Kv.store.exists(cache_key).value { false }

    send_notification(entitlements_message)

    ActiveRecord::Base.connected_to(role: :writing) do
      next_billing_period_start = billable_owner.next_metered_billing_cycle_starts_at
      # Cache expires when next billing period starts
      Codespaces::Kv.store.set(cache_key, Time.now.iso8601, expires: next_billing_period_start)
    end
  rescue Codespaces::VscsClient::BadResponseError => e
    # Cleanup if there is an error raised, then we should try to send again for the same codespace
    ActiveRecord::Base.connected_to(role: :writing) do
      Codespaces::Kv.store.del(T.must(notif_check_cache_key))
    end
    raise e
  end

  private

  def send_notification(message)
    client.notify_environment(id: codespace.guid, message: message, display_mode: "warning", modal: false)
  end

  memoize def client
    Codespaces::VscsClient.for_codespace(codespace)
  end

  class EntitlementsThresholdNotification
    include GitHub::Memoizer

    def self.notification_to_send(billable_owner:)
      self.new(billable_owner: billable_owner).notification_to_send
    end

    attr_accessor :billable_owner

    def notification_to_send
      return nil unless Codespaces::Policy.entitlements_feature_enabled?(billable_owner)

      if should_send_entitlements_compute_notification? && should_send_entitlements_storage_notification?
        return convert_inline_html_link_to_markdown(entitlements_compute_and_storage_notification), { compute: compute_threshold, storage: storage_threshold }
      end

      return [convert_inline_html_link_to_markdown(entitlements_compute_message), { compute: compute_threshold }] if should_send_entitlements_compute_notification?
      return [convert_inline_html_link_to_markdown(entitlements_storage_message), { storage: storage_threshold }] if should_send_entitlements_storage_notification?

      [nil, nil]
    end

    private

    def initialize(billable_owner:)
      @billable_owner = billable_owner
    end

    memoize def entitlements_compute_notification
      Billing::Notifications::UsageNotification.new(
        billable_owner, product: ::Billing::Notifications::CODESPACES_COMPUTE_PRODUCT
      )
    end

    memoize def entitlements_storage_notification
      Billing::Notifications::UsageNotification.new(
        billable_owner, product: ::Billing::Notifications::CODESPACES_STORAGE_PRODUCT
      )
    end

    memoize def should_send_entitlements_compute_notification?
      should_send_entitlements_notification?(notification: entitlements_compute_notification, type: :compute)
    end

    memoize def should_send_entitlements_storage_notification?
      should_send_entitlements_notification?(notification: entitlements_storage_notification, type: :storage)
    end

    memoize def compute_threshold
      entitlements_compute_notification.highest_priority_notification.threshold
    end

    memoize def storage_threshold
      entitlements_storage_notification.highest_priority_notification.threshold
    end

    def should_send_entitlements_notification?(notification:, type:)
      # If they are hitting their spending limit thresholds, they are well passed the entitlements threshold
      return false unless notification.spending_limit_notifications.empty?

      # We don't need to send an entitlements notification if there are none
      return false if notification.entitlement_notifications.empty?

      true
    end

    def entitlements_compute_message
      entitlements_message(entitlements_compute_notification)
    end

    def entitlements_storage_message
      entitlements_message(entitlements_storage_notification)
    end

    def entitlements_message(notification)
      [
        notification.highest_priority_notification.text.strip,
        notification.highest_priority_notification.action_text
      ].join(" ")
    end

    def entitlements_compute_and_storage_notification
      compute_threshold = entitlements_compute_notification.highest_priority_notification.threshold
      storage_threshold = entitlements_storage_notification.highest_priority_notification.threshold
      "You've used #{compute_threshold}% of included usage for Codespaces compute " +
      "and #{storage_threshold}% of Codespaces storage. " +
      entitlements_compute_notification.highest_priority_notification.action_text # should be the same for both
    end

    def convert_inline_html_link_to_markdown(message)
      message.gsub(/<a href="(.+?)">(.+?)<\/a>/, '[\2](\1)').gsub("&quot;", '"')
    end
  end
end
