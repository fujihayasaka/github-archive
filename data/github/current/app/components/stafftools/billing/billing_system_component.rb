# typed: strict
# frozen_string_literal: true

module Stafftools
  module Billing
    class BillingSystemComponent < ApplicationComponent

      sig { params(billable_entity: ::Billing::Types::Account, tag: Symbol).void }
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
        return false unless GitHub.billing_enabled?
        if billable_entity.billed_via_billing_platform?.nil?
          false
        else
          true
        end
      end

      private

      sig { returns(::Billing::Types::Account) }
      attr_reader :billable_entity

      sig { returns(String) }
      def message
        if billable_entity.billed_via_billing_platform?
          if billable_entity.is_a?(Business)
            link_to("Billing platform enabled", stafftools_enterprise_billing_path(billable_entity, anchor: "billing-platform-customer-information"))
          else
            link_to("Billing platform enabled", billing_stafftools_user_path(billable_entity, anchor: "billing-platform-customer-information"))
          end
        else
          "Billed via Meuse"
        end
      end
    end
  end
end
