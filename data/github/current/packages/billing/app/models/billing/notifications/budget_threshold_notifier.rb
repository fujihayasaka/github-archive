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
        "budget_slug": notification.budget.slug,
        "subscribed_recipient_ids": notification.budget.alert_recipients_user_ids.join(", "),
        "valid_recipient_ids": valid_recipients.collect(&:id).join(", "),
        "threshold": notification.threshold,
      }
    )

    ::BillingNotificationsMailer.budget_threshold_notification(
      user_emails: valid_recipient_emails,
      owner: notification.owner,
      email_context: email_context.serialize
    ).deliver_later

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

  sig { returns(T::Array[String]) }
  def valid_recipient_emails
    emails_to_send = valid_recipients.map(&:email).compact

    # Budget notifications for organizations go to billing managers and email recipients as well
    if notification.billable_owner.organization?
      # Add additional billing emails to send to
      notification.billable_owner.billing_users.each do |billing_user|
        emails_to_send << billing_user.billing_email
      end

      # Add email recipients
      emails_to_send.concat(notification.billable_owner.billing_external_emails.pluck(:email))

      return emails_to_send.uniq
    elsif notification.billable_owner.user?
      emails_to_send << notification.billable_owner.email
    end

    emails_to_send
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
end
