# typed: true
# frozen_string_literal: true

module Stafftools
  module Billing
    class PaymentStatusComponent < ApplicationComponent
      extend T::Sig

      sig { params(billable_entity: ::Billing::Interfaces::BillableEntity, tag: Symbol).void }
      def initialize(billable_entity:, tag: :li)
        @billable_entity = billable_entity
        @tag = tag
      end

      def call
        render Stafftools::StatusListItemComponent.new(status: status, message: message,
          test_selector: "payment-status", tag: tag)
      end

      def render?
        (!billable_entity.invoiced? && billable_entity.has_billing_record?) || billable_entity.dunning? || billable_entity.manual_dunning?
      end

      private

      attr_reader :billable_entity, :tag

      memoize def free_plan?
        billable_entity.free_plan?
      end

      memoize def no_billing_attempts?
        !billable_entity.dunning? && !billable_entity.manual_dunning?
      end

      memoize def charge_failing?
        billable_entity.paid_plan? && ((billable_entity.dunning? && billable_entity.billed_on) || billable_entity.manual_dunning?)
      end

      def status
        if free_plan?
          :success
        elsif no_billing_attempts?
          :success
        elsif charge_failing?
          :error
        else
          :neutral
        end
      end

      # Private: Show the current payment status of the account.
      #
      # Example:
      #
      # Charge failing. Will retry on 2000-11-11 and 2000-11-26
      # Charge failing. Will retry on 2000-11-26
      # Charge failing. No attempts remaining
      # Billing status: Unknown
      # Billing status: Good standing
      #
      # Returns a String.
      def message
        if free_plan?
          "Billing status: Free"
        elsif no_billing_attempts?
          "Billing status: Good standing"
        elsif charge_failing?
          if billable_entity.manual_dunning?
            "Manual payment due by #{billable_entity.manual_payment_due_date.strftime("%F")}"
          else
            tries = [0, ::User::BillingDependency::BILLING_ATTEMPTS_LIMIT - billable_entity.billing_attempts].max
            dates = [15, 7]
              .take(tries)
              .map { |day| (billable_entity.billed_on + day.days).strftime("%F") }
              .reverse
              .to_sentence
            text   = "Charge failing. Will retry on #{dates}" unless dates.blank?
            text ||= "Charge failing. No attempts remaining"
            text
          end
        else
          "Billing status: Unknown"
        end
      end
    end
  end
end
