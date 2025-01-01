# typed: strict
# frozen_string_literal: true

module Stafftools
  module Billing
    class BillingSystemComponent < ApplicationComponent
      extend T::Sig

      sig { params(billable_entity: ::Billing::Interfaces::BillableEntity, tag: Symbol).void }
      def initialize(billable_entity:, tag: :li)
        @billable_entity = billable_entity
        @tag = tag
      end

      sig { returns(String) }
      def call
        render Stafftools::StatusListItemComponent.new(
          status: :neutral,
          message: message,
          test_selector: "billing-system",
          tag: @tag,
        )
      end

      sig { returns(T::Boolean) }
      def render?
        if billable_entity.billed_via_billing_platform?.nil?
          false
        else
          true
        end
      end

      private

      sig { returns(::Billing::Interfaces::BillableEntity) }
      attr_reader :billable_entity

      sig { returns(String) }
      def message
        if billable_entity.billed_via_billing_platform?
          link_to("Billing platform enabled", stafftools_enterprise_billing_path(billable_entity, anchor: "billing-platform-customer-information"))
        else
          "Billed via Meuse"
        end
      end
    end
  end
end
