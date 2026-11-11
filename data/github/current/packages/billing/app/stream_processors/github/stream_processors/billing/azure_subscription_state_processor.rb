# typed: strict
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module Billing
      class AzureSubscriptionStateProcessor < SingleMessageProcessor
        include TransientErrorResiliency

        DEFAULT_GROUP_ID = T.let("github-#{Rails.env}-billing-azure_subscription_state_processor", String)
        DEFAULT_SUBSCRIBE_TO = /github\.billing\.v0\.AzureSubscriptionStateChange\Z/

        sig { params(kwargs: T.untyped).void }
        def setup(**kwargs)
          options[:group_id] ||= DEFAULT_GROUP_ID
          options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO
          options[:session_timeout] = 300.seconds
          options[:socket_timeout] = 305.seconds
          options[:start_from_beginning] = false

          self.transient_error_max_retries = 3
        end

        sig { override.params(message: GitHub::StreamProcessors::Message).void }
        def process_message(message)
          payload = message.value.with_indifferent_access
          sub_id = payload[:azure_subscription_id]
          status = payload[:subscription_status]
          fraud_flag = payload[:fraud_flag]

          return if sub_id.blank? || status.blank?

          GitHub.dogstats.increment(
            "billing.azure.spam_slam.signal_received",
            tags: ["status:#{status}"],
          )

          status = "FRAUD" if fraud_flag == "Yes"
          return unless %w[DEPROVISIONED DISABLED FRAUD].include?(status)

          customers = Customer.with_azure_subscription_id(sub_id).where(metered_via_azure: true).includes(:business, customer_accounts: :user).to_a
          return if customers.empty?

          enforce(status:, customers:, sub_id:)
        end

        private

        sig { params(status: String, customers: T::Array[::Customer], sub_id: String).void }
        def enforce(status:, customers:, sub_id:)
          customers.each do |customer|
            next disable_metered_via_azure(customer:, status:) unless owner = customer.billable_owner

            reason = ineligibility_reason_for(owner:)
            next record_skipped_enforcement(reason, sub_id:, customer:) if reason

            disable_metered_via_azure(customer:, status:)
            with_write do
              ::Billing::Kv.store.set(customer.invalid_azure_subscription_id_key, "true", expires: owner.next_metered_billing_cycle_starts_at)
            end
          end
        end

        sig { params(customer: Customer, status: String).void }
        def disable_metered_via_azure(customer:, status:)
          with_write do
            customer.update(metered_via_azure: false)
            customer.instrument("invalid_azure_subscription_detected", azure_subscription_status: status)
          end
          GitHub.dogstats.increment("billing.azure.spam_slam.enforced", tags: ["status:#{status}"])
        end

        sig { params(owner: ::Billing::Types::Account).returns(T.nilable(String)) }
        def ineligibility_reason_for(owner:)
          return "invoiced" if owner.invoiced?
          nil
        end

        sig { params(reason: String, sub_id: String, customer: Customer).void }
        def record_skipped_enforcement(reason, sub_id:, customer:)
          GitHub.dogstats.increment("billing.azure.spam_slam.skipped", tags: ["reason:#{reason}"])
          GitHub.logger.info({
            message: "Azure subscription enforcement skipped",
            fn: "AzureSubscriptionStateProcessor",
            azure_subscription_id: sub_id,
            reason: reason,
          })

          ::Billing::Azure::SendInvalidSubscriptionNotificationJob.perform_later(customer_id: customer.id)
        end
      end
    end
  end
end
