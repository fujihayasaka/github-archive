# typed: true
# frozen_string_literal: true

module Stafftools
  module Billing
    class MeteredServicesStatusComponent < ApplicationComponent
      extend T::Sig

      sig { params(billable_entity: ::Billing::Interfaces::BillableEntity, tag: Symbol).void }
      def initialize(billable_entity:, tag: :li)
        @billable_entity = billable_entity
        @tag = tag
      end

      def call
        render Stafftools::StatusListItemComponent.new(status: status, message: message,
          test_selector: "metered-services-status", tag: tag)
      end

      def render?
        billable_entity.invoiced?
      end

      private

      attr_reader :billable_entity, :tag

      memoize def metered_services_status?
        services_billable = billable_entity.metered_services_billable?

        if services_billable[:billable]
          return { status: :success, message: "Enabled" }
        elsif !services_billable[:billable]
          case services_billable[:reason]
          when :disabled, :suspended, :has_full_trade_restrictions, :has_any_trade_restrictions, :commercial_interaction_restriction
            return { status: :error, message: "Disabled (billable owner issue)" }
          when :metered_services_locked
            return { status: :error, message: "Disabled (metered services locked)" }
          when :metered_through_azure_with_no_azure_subscription_id, :non_azure_no_zuora_account, :non_azure_no_zuora_subscription
            return { status: :error, message: "Disabled (payment method issue)" }
          end
        end
        { status: :error, message: "Disabled (unknown reason)" }
      end

      def status
        metered_services_status?[:status]
      end

      def message
        "Metered services: #{metered_services_status?[:message]}"
      end
    end
  end
end
