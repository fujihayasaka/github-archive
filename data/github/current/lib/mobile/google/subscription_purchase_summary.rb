# typed: true
# frozen_string_literal: true

module Mobile
  module Google
    class SubscriptionPurchaseSummary < T::Struct
      class SubscriptionState < T::Enum
        enums do
          Unspecified = new
          PaymentPending = new
          Active = new
          Paused = new
          InGracePeriod = new
          OnHold = new
          Cancelled = new
          Expired = new
          PendingPurchaseCanceled = new
        end

        sig { params(subscription_state: String).returns(T.nilable(SubscriptionState)) }
        def self.from_subscription_state(subscription_state)
          case subscription_state
          when "SUBSCRIPTION_STATE_UNSPECIFIED"
            Unspecified
          when "SUBSCRIPTION_STATE_PENDING"
            PaymentPending
          when "SUBSCRIPTION_STATE_ACTIVE"
            Active
          when "SUBSCRIPTION_STATE_PAUSED"
            Paused
          when "SUBSCRIPTION_STATE_IN_GRACE_PERIOD"
            InGracePeriod
          when "SUBSCRIPTION_STATE_ON_HOLD"
            OnHold
          when "SUBSCRIPTION_STATE_CANCELED"
            Cancelled
          when "SUBSCRIPTION_STATE_EXPIRED"
            Expired
          when "SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED"
            PendingPurchaseCanceled
          end
        end

        sig { returns(T::Boolean) }
        def active?
          self == Active
        end
      end

      class Environment < T::Enum
        enums do
          Production = new
          Test = new
        end

        sig { params(test_purchase: T.nilable(::Google::Apis::AndroidpublisherV3::TestPurchase)).returns(Environment) }
        def self.from_test_purchase(test_purchase)
          if test_purchase
            Environment::Test
          else
            Environment::Production
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

        sig { returns(T::Boolean) }
        def cancel_after_30_minutes?
          test?
        end
      end

      class CopilotSKU < T::Enum
        enums do
          CopilotPro = new
          CopilotProPlus = new
        end

        sig { params(line_item: T.nilable(::Google::Apis::AndroidpublisherV3::SubscriptionPurchaseLineItem)).returns(T.nilable(CopilotSKU)) }
        def self.from_line_item(line_item:)
          return unless line_item

          case line_item.product_id
          when Mobile::Google::COPILOT_MONTHLY_SKU_ID
            CopilotPro
          when Mobile::Google::COPILOT_PRO_PLUS_SKU_ID
            CopilotProPlus
          end
        end

        sig { returns(T::Boolean) }
        def copilot_pro?
          self == CopilotPro
        end

        sig { returns(T::Boolean) }
        def copilot_pro_plus?
          self == CopilotProPlus
        end
      end

      const :environment, Environment
      const :active_copilot_purchase_token, T.nilable(String)
      const :active_copilot_sku, T.nilable(CopilotSKU)

      def copilot?
        active_copilot_purchase_token.present?
      end

      def production?
        environment == Environment::Production
      end

      sig do
        params(
          subscription_purchase: ::Google::Apis::AndroidpublisherV3::SubscriptionPurchaseV2,
          purchase_token: String
        ).returns(SubscriptionPurchaseSummary)
      end
      def self.from_subscription_purchase_v2(subscription_purchase, purchase_token)
        environment = Environment.from_test_purchase(subscription_purchase.test_purchase)
        subscription_state = SubscriptionState.from_subscription_state(subscription_purchase.subscription_state)
        is_subscription_active = subscription_state&.active?
        active_copilot_purchase_token = purchase_token if is_subscription_active
        active_copilot_line_item = subscription_purchase.line_items.find do |line_item|
          DateTime.parse(line_item.expiry_time) > DateTime.now
        end
        active_copilot_sku = CopilotSKU.from_line_item(line_item: active_copilot_line_item) if is_subscription_active && active_copilot_line_item

        new(
          environment:,
          active_copilot_purchase_token:,
          active_copilot_sku:
        )
      end
    end
  end
end
