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
      # TODO: Re-implement the notification logic using usage data from Billing Platform API
      # Tracking issue with commit ref: https://github.com/github/gitcoin/issues/24239

      [nil, nil]
    end

    private

    def initialize(billable_owner:)
      @billable_owner = billable_owner
    end
  end
end
