# typed: true
# frozen_string_literal: true

module Platform
  module Helpers
    module Enterprise
      extend T::Helpers

      requires_ancestor { Object }

      # Used to prevent access to specific schema for Businesses without the "full" seats plan type.
      def business_full_plan_required!(business)
        return if GitHub.enterprise? || business.blank?

        message = "This schema is unavailable for your enterprise."
        raise Platform::Errors::Forbidden.new(message) unless business.seats_plan_full?
      end

      # Checks to see if a Business is downgraded to the free plan, or suspended, and raises the appropriate error.
      def ensure_business_can_use_api!(business, message = nil)
        ensure_business_not_suspended!(business, message)
        ensure_business_not_downgraded_to_free_plan!(business, message)
        ensure_business_payment_completed!(business, message)
      end

      # Raise Platform::Errors::Forbidden if a Business is downgraded to the free plan.
      def ensure_business_not_downgraded_to_free_plan!(business, message = nil)
        message ||= "This schema is unavailable for enterprises downgraded to the free plan."

        if business&.downgraded_to_free_plan?
          raise Platform::Errors::Forbidden.new message
        end
      end

      # Raise Platform::Errors::Forbidden if a Business is suspended.
      def ensure_business_not_suspended!(business, message = nil)
        return if GitHub.enterprise?

        message ||= "This schema is unavailable for suspended enterprises."

        if business&.suspended?
          raise Platform::Errors::Forbidden.new message
        end
      end

      def ensure_business_payment_completed!(business, message = nil)
        if business&.upgrading_from_organization?
          message ||= "This schema is unavailable for enterprises upgraded from an organization, while payment has not been completed."
          raise Platform::Errors::Forbidden.new message
        elsif business&.being_created_from_coupon?
          message ||= "This schema is unavailable for enterprises while coupon redemption has not been completed."
          raise Platform::Errors::Forbidden.new message
        end
      end

      def ensure_business_not_an_emu!(business, message = nil)
        return if GitHub.enterprise? || business.blank?
        return unless business.enterprise_managed?

        message ||= "This schema is unavailable for Enterprise Managed User (EMU) enterprises."
        raise Platform::Errors::Forbidden.new message
      end
    end
  end
end
