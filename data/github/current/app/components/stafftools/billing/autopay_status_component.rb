# typed: true
# frozen_string_literal: true

module Stafftools
  module Billing
    class AutopayStatusComponent < ApplicationComponent
      extend T::Sig

      sig do
        params(
          billable_entity: ::Billing::Interfaces::BillableEntity,
          tag: Symbol
        ).void
      end
      def initialize(billable_entity:, tag: :li)
        @billable_entity = billable_entity
        @tag = tag
      end

      def call
        render Stafftools::StatusListItemComponent.new(
          status: :success,
          message: status_message,
          test_selector: "autopay-status",
          tag: tag
        )
      end

      def render?
        !billable_entity.invoiced? && billable_entity.has_billing_record?
      end

      private

      attr_reader :billable_entity, :tag

      def autopay_enabled?
        billable_entity&.auto_pay_reasons.none?
      end

      def status_message
        if autopay_enabled?
          "Autopay: Enabled"
        else
          autopay_reasons = ActiveSupport::Inflector.titleize(billable_entity.auto_pay_reasons.join(", "))
          "Autopay: Disabled (#{autopay_reasons})"
        end
      end
    end
  end
end
