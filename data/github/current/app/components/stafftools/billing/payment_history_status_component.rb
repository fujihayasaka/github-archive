# typed: true
# frozen_string_literal: true

module Stafftools
  module Billing
    class PaymentHistoryStatusComponent < ApplicationComponent

      sig { params(billable_entity: ::Billing::Interfaces::BillableEntity, tag: Symbol).void }
      def initialize(billable_entity:, tag: :li)
        @billable_entity = billable_entity
        @tag = tag
      end

      def call
        render Stafftools::StatusListItemComponent.new(status: status, message: message,
          test_selector: "payment-history-status", tag: tag)
      end

      private

      attr_reader :billable_entity, :tag

      memoize def has_billing_record?
        billable_entity.has_billing_record?
      end

      def status
        has_billing_record? ? :success : :neutral
      end

      def message
        if has_billing_record?
          "Payment history: Has #{billable_entity.external_subscription_type&.titleize} record"
        else
          "Payment history: No billing record"
        end
      end
    end
  end
end
