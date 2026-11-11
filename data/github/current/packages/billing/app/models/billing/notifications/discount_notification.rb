# typed: true
# frozen_string_literal: true

module Billing
  module Notifications
    class DiscountNotification
      include GitHub::Memoizer

      attr_reader :result, :owner, :billable_owner, :discount, :context, :actor

      sig do
        params(
          discount: Billing::Platform::Api::Discount,
          context: T.nilable(T.any(::User, Organization, ::Business, Repository)),
          actor: T.nilable(::User)
        ).void
      end
      def initialize(discount:, context: nil, actor: nil)
        @discount = discount
        @owner = discount.owner
        @context = context || owner
        @billable_owner = owner&.billable_owner
        @result = threshold_result
        @actor = actor
      end

      sig { returns(T.nilable(Billing::Notifications::DiscountNotificationSerializer)) }
      memoize def serialize
        return nil unless has_result?

        DiscountNotificationSerializer.new(self)
      end

      alias_method :highest_priority_notification, :serialize

      sig { returns(T::Boolean) }
      def has_result?
        result.present?
      end

      sig { returns(Billing::Platform::Api::Discount) }
      def active_discount
        discount
      end

      private

      sig { returns(T.nilable(Billing::Notifications::Result)) }
      def threshold_result
        return unless discount.owner.present?
        return unless discount.visible_to?(context)
        return unless discount.current_amount.positive?
        return unless billable_owner.present?
        return if billable_owner.plan.nil?
        return if billable_owner.plan.legacy?

        Billing::Notifications::Result.new(
          value: discount.current_percentage,
          threshold: discount.threshold_percentage,
          tags: [discount.product_name, discount.pricing_target_type, discount.discount_type],
          context: {
            used: discount.current_amount,
            available: discount.target_amount
          }
        )
      end
    end
  end
end
