# typed: true
# frozen_string_literal: true

module Stafftools
  module Billing
    class BillableStateStatusComponent < ApplicationComponent
      sig { params(billable_entity: ::Billing::Interfaces::BillableEntity, tag: Symbol).void }
      def initialize(billable_entity:, tag: :li)
        @billable_entity = billable_entity
        @tag = tag
      end

      def call
        render Stafftools::StatusListItemComponent.new(
          status: status,
          message: message_with_link_and_tooltip,
          test_selector: "billable-state-status",
          tag: tag
        )
      end

      private

      attr_reader :billable_entity, :tag
      delegate :customer, to: :billable_entity

      def status
        case billable_state
        when :billable
          :success
        when :not_billable
          :error
        else
          :neutral
        end
      end

      def message
        case billable_state
        when :billable
          "Enterprise status: Billable"
        when :not_billable
          "Enterprise status: Not billable"
        else
          "Enterprise status: Unknown"
        end
      end

      def message_with_link_and_tooltip
        if billable_state == :not_billable
          route = resolve_not_billable_route
          tooltip = not_billable_tooltip
          helpers.link_to(
            message,
            route,
            title: tooltip,
            class: "status-message-link"
          )
        else
          message
        end
      end

      def resolve_not_billable_route
        "/stafftools/enterprises/#{billable_entity.slug}/billing"
      end

      def not_billable_tooltip
        if customer&.requires_azure_subscription? && !customer.azure_subscription_id.present?
          "No valid Azure subscription ID found"
        elsif !customer&.valid_zuora_with_payment?
          "No valid Zuora subscription with payment found"
        elsif customer&.billing_locked?
          "Billing is locked"
        else
          "Click to resolve not billable status"
        end
      end

      def billable_state
        return :unknown unless customer

        if customer.requires_azure_subscription?
          return customer.azure_subscription_id.present? ? :billable : :not_billable
        end

        if customer.valid_zuora_with_payment? && !customer.billing_locked?
          :billable
        else
          :not_billable
        end
      end
    end
  end
end
