# typed: true
# frozen_string_literal: true

module Billing
  class MeteredThresholdNotifier
    def initialize(owner_id:, product:, owner_type: "User")
      @owner_type = owner_type
      @product = product

      ActiveRecord::Base.connected_to(role: :reading) do
        if owner_type == "Business"
          @owner = Business.find_by(id: owner_id)
        else
          owner = User.find_by(id: owner_id)
          @billable_owner = owner&.billable_owner
          @owner = if FeatureFlag.vexi.enabled_or_raise?(:ghe_spending_limits, @billable_owner) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
            owner
          else
            @billable_owner
          end
        end
      end
    end

    def notify_if_applicable
      return if owner_type == "Business"
      return unless owner
      return if billable_owner.plan.legacy?

      cache_key = "billing:metered_threshold_notifier:#{owner}:#{owner.id}:#{product}"
      if GitHub.legacy_redis.set(cache_key, 1, nx: true, ex: 60)
        GitHub.dogstats.increment("billing.metered_threshold_notifier_cache.checked", tags: ["owner_type:#{owner_type}"])
        notification = Billing::Notifications::UsageNotification.new(owner, product: product)
        Billing::Notifications::UsageNotifier.new(owner, product: product, usage_notification: notification).notify_if_applicable
        also_notify_business_if_applicable
      else
        GitHub.dogstats.increment("billing.metered_threshold_notifier_cache.duplicate", tags: ["owner_type:#{owner_type}"])
        nil
      end
    end

    def notify_for_business_if_applicable
      ActiveRecord::Base.connected_to(role: :reading) do
        return if owner.plan.legacy?

        cache_key = "billing:metered_threshold_notifier:#{owner_type.downcase}:#{owner}:#{owner.id}:#{product}"
        if GitHub.legacy_redis.set(cache_key, 1, nx: true, ex: 60)
          GitHub.dogstats.increment("billing.metered_threshold_notifier_cache.checked", tags: ["owner_type:#{owner_type}"])
          notification = Billing::Notifications::UsageNotification.new(owner, product: product)
          Billing::Notifications::UsageNotifier.new(owner, product: product, usage_notification: notification).notify_if_applicable
        else
          GitHub.dogstats.increment("billing.metered_threshold_notifier_cache.duplicate", tags: ["owner_type:#{owner_type}"])
          nil
        end
      end
    end

    private

    def also_notify_business_if_applicable
      ActiveRecord::Base.connected_to(role: :reading) do
        return unless owner.delegate_billing_to_business?

        business = owner.business
        notification = Billing::Notifications::UsageNotification.new(business, product: product)
        Billing::Notifications::UsageNotifier.new(business, product: product, usage_notification: notification).notify_if_applicable
      end
    end

    attr_reader :billable_owner, :owner, :product, :owner_type
  end
end
