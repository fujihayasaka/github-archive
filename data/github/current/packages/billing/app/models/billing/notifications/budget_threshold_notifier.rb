# typed: strict
# frozen_string_literal: true

class Billing::Notifications::BudgetThresholdNotifier
  include GitHub::Memoizer
  include ActionView::Helpers::NumberHelper

  sig { params(notification: Billing::Notifications::BudgetNotificationSerializer).void }
  def initialize(notification:)
    @notification = notification
  end

  sig { void }
  def call
    email_identifier = build_email_identifier
    return if email_sent?(email_identifier)

    GitHub.logger.info(
      "Budget threshold notification enqueued",
      {
        "gh.billing.budget.slug": notification.budget.slug,
        "gh.billing.budget.recipients_user_ids": notification.budget.alert_recipients_user_ids.join(", "),
        "gh.billing.budget.valid_recipient_ids": valid_recipients.collect(&:id).join(", "),
        "gh.billing.budget.threshold": notification.threshold,
        "gh.customer.id": notification.billable_owner.customer.id,
        "gh.billing.budget.target_type": notification.budget.target_type,
        "gh.billing.budget.target_id": notification.budget.target_id,
        "gh.billing.budget.product_name": notification.budget.pricing_target_id,
      }
    )

    ::BillingNotificationsMailer.budget_threshold_notification(
      recipients: valid_recipients,
      owner: notification.owner,
      email_context: email_context.serialize
    ).deliver_later

    instrument_send
    mark_email_sent(email_identifier)
  end

  private

  sig { returns(Billing::Notifications::BudgetNotificationSerializer) }
  attr_reader :notification

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

  sig { returns(String) }
  def build_email_identifier
    # WARNING: changing the parts of the key in this method
    # would bust the email key used to prevent duplicates.
    # Meaning that users may receive duplicate notifications

    [
      notification.budget.slug,
      notification.threshold,
      notification.owner.current_metered_billing_cycle_starts_at.to_date,
    ].compact.join("-")
  end

  sig { returns(T::Array[User]) }
  def valid_recipients
    vnext_individual = notification.billable_owner.user?
    recipient_ids = notification.budget.alert_recipients_user_ids.map(&:to_i)
    owner_member_ids = if notification.billable_owner.organization?
      notification.billable_owner.member_ids
    elsif vnext_individual
      [notification.billable_owner.id]
    else
      notification.billable_owner.admin_and_organization_member_ids
    end

    member_recipient_ids = recipient_ids.intersection(owner_member_ids)
    User.where(id: member_recipient_ids).to_a
  end

  sig { returns(Billing::Notifications::ThresholdEmailContext) }
  memoize def email_context
    Billing::Notifications::ThresholdEmailContext.new(
      threshold: notification.threshold,
      progress_bar_details_text: notification.progress_bar_details_text,
      progress_bar_title: notification.progress_bar_title,
      text: notification.text,
      usage_reset_date_text: notification.usage_reset_date_text,
      mail_subject: notification.mail_subject,
      mail_icon: notification.mail_icon,
      mail_product_title: notification.mail_product_title,
    )
  end

  sig { void }
  def instrument_send
    billable_owner = notification.billable_owner

    payload = {
      billable_owner.event_prefix => billable_owner,
      :product =>  notification.budget.pricing_target_id,
      :threshold_level => notification.threshold,
    }

    GitHub.dogstats.increment("billing.metered_usage_email_sent", tags: ["product:#{notification.budget.pricing_target_id}", "threshold_level:#{notification.threshold}"])
    GitHub.instrument("billing.metered_usage_email_sent", payload)
  end
end
