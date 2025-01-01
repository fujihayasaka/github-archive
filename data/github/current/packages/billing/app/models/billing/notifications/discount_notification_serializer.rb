# typed: true
# frozen_string_literal: true

module Billing
  module Notifications
    class DiscountNotificationSerializer < BaseThresholdNotificationSerializer
      include ::Api::Serializer::BillingDependency

      delegate :discount, to: :notification

      sig { returns(Integer) }
      def threshold
        discount.threshold_percentage
      end

      sig { override.returns(T.untyped) }
      def resource
        discount
      end

      sig { override.returns(String) }
      def resource_type
        "discount"
      end

      sig { override.returns(String) }
      def mail_subject
        "#{threshold}% of #{metered_service_name} discount threshold reached"
      end

      sig { override.returns(String) }
      def mail_product_title
        "Discount usage"
      end

      sig { override.returns(String) }
      def metered_service_name
        get_credit_description([{ id: discount.pricing_target_id }])
      end

      sig { override.returns(String) }
      def progress_bar_title
        "Discount"
      end

      sig { override.returns(Symbol) }
      def variant
        return :danger if discount.fully_applied?

        :warning
      end
    end
  end
end
