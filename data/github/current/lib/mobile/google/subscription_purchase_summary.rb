# typed: true
# frozen_string_literal: true

module Mobile
  module Google
    class SubscriptionPurchaseSummary < T::Struct


      class PaymentState < T::Enum

        enums do
          PaymentPending = new
          PaymentReceived = new
          FreeTrial = new
          PendingDeferred = new
          CancelledOrExpired = new
        end

        sig { params(integer: T.nilable(Integer)).returns(PaymentState) }
        def self.from_raw(integer)
          case integer
          when 0 then PaymentPending
          when 1 then PaymentReceived
          when 2 then FreeTrial
          when 3 then PendingDeferred
          else CancelledOrExpired
          end
        end
      end

      class Environment < T::Enum

        enums do
          Production = new
          Test = new
        end

        sig { params(purchase_type: T.nilable(Integer)).returns(Environment) }
        def self.from_purchase_type(purchase_type)
          case purchase_type
          when 0 then Environment::Test
          else Environment::Production
          end
        end

        sig { returns(T::Boolean) }
        def production?
          self == Production
        end

        sig { returns(T::Boolean) }
        def test?
          !production?
        end
      end

      const :environment, Environment
      const :active_copilot_purchase_token, T.nilable(String)

      def copilot?
        active_copilot_purchase_token.present?
      end

      def production?
        environment == Environment::Production
      end

      sig { params(subscription_purchase: ::Google::Apis::AndroidpublisherV3::SubscriptionPurchase, purchase_token: String).returns(SubscriptionPurchaseSummary) }
      def self.from_subscription_purchase(subscription_purchase, purchase_token)
        environment = Environment.from_purchase_type(subscription_purchase.purchase_type)
        payment_state = PaymentState.from_raw(subscription_purchase.payment_state)
        expiry_time_millis = subscription_purchase.expiry_time_millis
        current_time_millis = (Time.now.to_f * 1000).to_i
        is_subscription_active = expiry_time_millis > current_time_millis
        is_payment_received = payment_state == PaymentState::PaymentReceived
        active_copilot_purchase_token = if is_subscription_active && is_payment_received
          purchase_token
        else
          nil
        end
        new(
          environment:,
          active_copilot_purchase_token:
        )
      end
    end
  end
end
