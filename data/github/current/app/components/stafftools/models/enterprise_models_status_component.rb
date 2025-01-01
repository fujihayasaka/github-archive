# typed: true
# frozen_string_literal: true

module Stafftools
  module Models
    class EnterpriseModelsStatusComponent < ApplicationComponent

      sig { params(billable_entity: ::Billing::Interfaces::BillableEntity, tag: Symbol).void }
      def initialize(billable_entity:, tag: :li)
        @billable_entity = billable_entity
        @tag = tag
      end

      def call
        render Stafftools::StatusListItemComponent.new(status: status, message: message,
          test_selector: "models-billing-status", tag: @tag)
      end

      private

      attr_reader :billable_entity

      sig { returns(T::Boolean) }
      memoize def models_access_enabled?
        billable_entity.models_access_enabled?
      end

      sig { returns(Symbol) }
      def status
        if models_access_enabled?
          :success
        else
          :neutral
        end
      end

      sig { returns(String) }
      def message
        if models_access_enabled?
          "Models is enabled"
        else
          "Models is not enabled"
        end
      end
    end
  end
end
