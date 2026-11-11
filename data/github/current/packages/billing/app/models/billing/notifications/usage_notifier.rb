# typed: strict
# frozen_string_literal: true

class Billing::Notifications::UsageNotifier
  include ActionView::Helpers::NumberHelper

  sig { params(owner: Billing::Types::Account, product: T.nilable(String), usage_notification: T.nilable(Billing::Notifications::UsageNotification)).void }
  def initialize(owner, product: nil, usage_notification: nil)
    @owner = T.let(
      FeatureFlag.vexi.enabled_or_raise?(:ghe_spending_limits, owner.billable_owner) ? owner : owner.billable_owner, # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      Billing::Types::Account
    )
    @billable_owner = T.let(owner.billable_owner, Billing::Types::Account)
    @product = product
    @usage_notification = usage_notification
    @content = T.let(usage_notification&.highest_priority_notification, T.nilable(Billing::Notifications::UsageNotificationContent))
  end

  sig { void }
  def notify_if_applicable
    content = self.content
    return if billable_owner.plan.legacy?
    return if org_owner_for_enterprise_content?

    # Need to remove non-nil email sent keys
    # Otherwise, a customer could trip threshold email (say 75%)
    # Raise their spending limits and lower their usage (to 50%)
    # Then return to threshold (75%)
    # email_sent? would find 75% email already set
    if !content || !product
      remove_non_current_email_sent_keys
      return
    end

    return unless budget_allows_notification?
    email_key = email_identifier(current_level)

    return if email_sent?(email_key)

    BillingNotificationsMailer.resources_usage(owner, content).deliver_later

    if FeatureFlag.vexi.enabled_or_raise?(:ghe_spending_limits, billable_owner) && owner.delegate_billing_to_business? # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      BillingNotificationsMailer.resources_usage(billable_owner, content, content_owner: owner).deliver_later
    end

    mark_email_sent(email_key)

    instrument_send
    remove_non_current_email_sent_keys
    send_invoiced_slack_notification(content.slack_notification_message)
  end

  sig { returns(T::Boolean) }
  def within_entitlements?
    content = self.content
    return true unless content
    content.within_entitlements?
  end

  sig { returns(T.nilable(String)) }
  def notification_scope
    content&.scope || product
  end

  sig { returns(T.nilable(String)) }
  def current_level
    content = self.content
    return nil unless content
    Billing::Notifications::THRESHOLDS[content.threshold]
  end

  # spending-limit-error-user-397-2019-10-01-1
  # actions-info-business-408-2019-10-01
  # WARNING: changing the parts of the key in this method
  # would mean that users may receive notifications as this would essentially
  # bust the email key used to prevent duplicates.
  sig { params(level: T.nilable(String)).returns(String) }
  def email_identifier(level)
    raise ArgumentError, "Must set product for email notifications" if product.nil?

    budget = usage_notification&.active_budget

    [
      notification_scope,
      level,
      owner.class.to_s.downcase,
      owner.id,
      owner.current_metered_billing_cycle_starts_at.to_date,
      budget&.product,
      budget&.spending_limit_in_subunits
    ].compact.join("-")
  end

  sig { params(key: String).returns(T::Boolean) }
  def email_sent?(key)
    # If there is an issue retrieving the key assume email has been sent
    # as to not spam users with emails when KV is having issues.
    Billing::Kv.store.exists(key).value { true }
  end

  sig { params(key: String).void }
  def mark_email_sent(key)
    ActiveRecord::Base.connected_to(role: :writing) do
      Billing::Kv.store.set(key, Time.now.to_s, expires: 60.days.from_now)
    end
  end

  sig { void }
  def instrument_send
    downcased_class_name = owner.class.to_s.downcase
    formatted_class_name = downcased_class_name == "organization" ? :org : downcased_class_name.to_sym

    payload = {
      formatted_class_name => owner,
      :product => notification_scope,
      :threshold_level => current_level,
      :first_day_in_metered_cycle => owner.current_metered_billing_cycle_starts_at.to_date,
      :paid_threshold => !within_entitlements?
    }

    GitHub.dogstats.increment("billing.metered_usage_email_sent", tags: ["product:#{payload[:product]}", "threshold_level:#{payload[:threshold_level]}", "paid_threshold:#{payload[:paid_threshold]}", "is_usage_notifier: true"])
    GitHub.instrument("billing.metered_usage_email_sent", payload)
  end

  sig { params(slack_notification_message: String).void }
  def send_invoiced_slack_notification(slack_notification_message)
    return unless billable_owner.invoiced?

    Billing::InvoicedMeteredBillingSlackNotifier.new(
      owner: owner,
      paid: within_entitlements?,
      usage_message: slack_notification_message
    ).send_notification
  end

  sig { void }
  def remove_non_current_email_sent_keys
    keys_to_delete = []

    [nil,
     Billing::Notifications::LEVEL_INFO,
     Billing::Notifications::LEVEL_WARN,
     Billing::Notifications::LEVEL_ERROR].each do |l|
       if current_level != l
         keys_to_delete << email_identifier(l)
       end
     end

    Billing::Kv.store.mexists(keys_to_delete).map do |values|
      return unless values.any?

      ActiveRecord::Base.connected_to(role: :writing) do
        Billing::Kv.store.mdel(keys_to_delete)
      end
    end
  end

  private

  sig { returns(T::Boolean) }
  def org_owner_for_enterprise_content?
    return false unless FeatureFlag.vexi.enabled_or_raise?(:ghe_spending_limits, billable_owner) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
    usage_notification = self.usage_notification

    owner.delegate_billing_to_business? && (
      content&.within_entitlements || (
        usage_notification && usage_notification.active_budget.owner.is_a?(Business)
      )
    )
  end

  sig { returns(T::Boolean) }
  def budget_allows_notification?
    budget = usage_notification&.active_budget

    return false if FeatureFlag.vexi.enabled_or_raise?(:ghe_spending_limits, billable_owner) && budget&.notify_spending == false # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
    return false if content&.within_entitlements && budget&.included_usage_notification == false
    return false if !content&.within_entitlements && budget&.paid_usage_notification == false

    true
  end

  sig { returns(Billing::Types::Account) }
  attr_reader :owner
  sig { returns(Billing::Types::Account) }
  attr_reader :billable_owner
  sig { returns(T.nilable(String)) }
  attr_reader :product
  sig { returns(T.nilable(Billing::Notifications::UsageNotification)) }
  attr_reader :usage_notification
  sig { returns(T.nilable(Billing::Notifications::UsageNotificationContent)) }
  attr_reader :content
end
