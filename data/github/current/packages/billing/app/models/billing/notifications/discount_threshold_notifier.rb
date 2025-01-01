# typed: strict
# frozen_string_literal: true

module Billing
  module Notifications
    class DiscountThresholdNotifier
      include GitHub::Memoizer

      sig { params(notification: Billing::Notifications::DiscountNotificationSerializer).void }
      def initialize(notification:)
        @notification = notification
      end

      sig { void }
      def call
        email_identifier = build_email_identifier
        return if email_sent?(email_identifier)

        GitHub.logger.info(
          "Discount threshold notification enqueued",
          {
            "gh.billing.discount.slug": notification.discount.slug,
            "gh.billing.discount.threshold": notification.threshold,
            "gh.billing.discount.resource_type": notification.discount.resource_type,
            "gh.customer.id": notification.billable_owner.customer.id,
          }
        )

        ::BillingNotificationsMailer.discount_threshold_notification(
          owner: notification.owner,
          email_context: email_context.serialize
        ).deliver_later

        GitHub.logger.info(
          "Enqueued discount threshold notification",
          "gh.billing.email_identifier_key": email_identifier
        )

        instrument_send
        mark_email_sent(email_identifier)
      end

      private

      sig { returns(Billing::Notifications::DiscountNotificationSerializer) }
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
          notification.discount.slug,
          notification.threshold,
          notification.owner&.current_metered_billing_cycle_starts_at&.to_date,
        ].compact.join("-")
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
          :product => notification.metered_service_name,
          :discountThreshold => notification.threshold,
          :action => "billing.discount_threshold_email_sent"
        }

        GitHub.dogstats.increment("billing.discount_threshold_email_sent", tags: ["product:#{notification.metered_service_name}", "threshold_level:#{notification.threshold}"])
        GitHub.instrument("billing.discount_threshold_email_sent", payload)
      end
    end
  end
end
