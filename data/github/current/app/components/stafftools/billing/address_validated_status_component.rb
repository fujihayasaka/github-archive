# typed: strict
# frozen_string_literal: true

module Stafftools
  module Billing
    class AddressValidatedStatusComponent < ApplicationComponent
      extend T::Sig

      DISPLAY_FORMAT = "on %Y-%m-%d at %I:%M %p %Z"

      sig { params(billable_entity: ::Billing::Types::Account, tag: Symbol).void }
      def initialize(billable_entity:, tag: :li)
        @billable_entity = billable_entity
        @tag = tag
      end

      sig { returns(ActiveSupport::SafeBuffer)  }
      def call
        render Stafftools::StatusListItemComponent.new(status: status, message: message,
          test_selector: "address-validated-status", tag: tag)
      end

      sig { returns(T::Boolean)  }
      def render?
        return false unless profile.present?

        profile.country_is_united_states?
      end

      private

      sig { returns(::Billing::Types::Account) }
      attr_reader :billable_entity

      sig { returns(Symbol) }
      attr_reader :tag

      sig { returns(AccountScreeningProfile) }
      memoize def profile
        billable_entity.trade_screening_record
      end

      sig { returns(Symbol)  }
      def status
        return :success if profile.validated_for_sales_tax?

        :neutral
      end

      sig { returns(String)  }
      def message
        validated_at = profile.billing_address_validated_at

        if validated_at
          validated_at_in_tz = validated_at.in_time_zone(GitHub::Billing.timezone)
          "Address validated: #{validated_at_in_tz.strftime(DISPLAY_FORMAT)}"
        else
          "Address validated: No"
        end
      end
    end
  end
end
