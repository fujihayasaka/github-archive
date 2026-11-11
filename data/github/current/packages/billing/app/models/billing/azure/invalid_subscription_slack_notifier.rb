# typed: strict
# frozen_string_literal: true

module Billing
  module Azure
    class InvalidSubscriptionSlackNotifier
      include UrlHelpers

      NOTIFICATION_SLACK_CHANNEL = "#sales-operations"

      sig { params(customer: ::Customer).void }
      def initialize(customer:)
        @customer = customer
      end

      sig { void }
      def send_notification
        return unless owner
        return if already_notified?

        GitHub::Chatterbox.client.colored_say(NOTIFICATION_SLACK_CHANNEL, Chatterbox::YELLOW, message)
        ::Billing::Kv.store.set(alert_key, GitHub::Billing.today.to_s, expires: 30.days.from_now)
      end

      private

      sig { returns(::Customer) }
      attr_reader :customer

      sig { returns(T.nilable(T.any(User, Business))) }
      def owner
        @owner ||= T.let(customer.billable_owner, T.nilable(T.any(User, Business)))
      end

      sig { returns(String) }
      def message
        "[Azure Metered Billing] Invalid Azure subscription for #{account_stafftools_link}\n" \
        "Subscription ID: #{customer.azure_subscription_id}\n" \
        "This account is metered via Azure and invoiced. We can't bill this account until a valid Azure subscription is linked."
      end

      sig { returns(String) }
      def account_stafftools_link
        account = T.must(owner)
        url_options = { host: "admin.github.com", protocol: "https" }
        url = if account.is_a?(Business)
          stafftools_enterprise_url(account, **url_options)
        else
          stafftools_user_url(account, **url_options)
        end
        "<#{url}|#{account.name}>"
      end

      sig { returns(T::Boolean) }
      def already_notified?
        !!::Billing::Kv.store.get(alert_key).value!
      end

      sig { returns(String) }
      def alert_key
        "azure-invalid-sub.alert.#{customer.azure_subscription_id}"
      end
    end
  end
end
