# typed: true
# frozen_string_literal: true

module Stafftools
  module Billing
    class MeteredViaAzureStatusComponent < ApplicationComponent
      extend T::Sig

      sig { params(billable_entity: ::Billing::Interfaces::BillableEntity, tag: Symbol).void }
      def initialize(billable_entity:, tag: :li)
        @billable_entity = billable_entity
        @tag = tag
      end

      def call
        render Stafftools::StatusListItemComponent.new(status: status, message: message,
          test_selector: "metered-via-azure-status", tag: tag)
      end

      def render?
        metered_via_azure? && billable_entity.organization? && !billable_entity.delegate_billing_to_business?
      end

      private

      attr_reader :billable_entity, :tag

      memoize def metered_via_azure?
        billable_entity.customer&.metered_via_azure? || false
      end

      def status
        metered_via_azure? ? :success : :neutral
      end

      def message
        if metered_via_azure?
          "Metered via Azure: Enabled"
        else
          "Metered via Azure: Disabled"
        end
      end
    end
  end
end
