# typed: true
# frozen_string_literal: true

module Stafftools
  module Licensing
    class LicensingModelComponent < ApplicationComponent
      extend T::Sig

      sig { params(billable_entity: ::Billing::Interfaces::BillableEntity, tag: Symbol).void }
      def initialize(billable_entity:, tag: :li)
        @billable_entity = billable_entity
        @tag = tag
      end

      def call
        render Stafftools::StatusListItemComponent.new(status: status, message: message,
          test_selector: "license-type-status", tag: tag)
      end

      private

      attr_reader :billable_entity, :tag

      memoize def metered_ghe?
        billable_entity.metered_plan? || false
      end

      def status
        :success
      end

      def message
        licensing_model = metered_ghe? ? "Metered" : "Volume"
        "Licensing model: #{licensing_model}"
      end
    end
  end
end
