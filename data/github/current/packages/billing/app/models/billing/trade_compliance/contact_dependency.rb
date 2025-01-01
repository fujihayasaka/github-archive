# typed: strict
# frozen_string_literal: true

module Billing::TradeCompliance
  module ContactDependency
    extend ActiveSupport::Concern
    extend T::Helpers
    extend T::Sig

    abstract!

    requires_ancestor { Billing::Contact }

    included do
      T.bind(self, T.class_of(Billing::Contact))

      # Trade screening validations
      validate :valid_for_individual_trade_screening, if: :individual_trade_screening_validation?
      validate :valid_for_entity_trade_screening, if: :entity_trade_screening_validation?

      private

      sig { returns(T::Boolean) }
      def individual_trade_screening_validation?
        # for some reason rails puts custom validation context in a Hash, while built in validation
        # context is a symbol. This is only the case because the validation context is being used from the dependency
        return validation_context.dig(:context) == :individual_trade_screening if validation_context.is_a?(Hash)

        validation_context == :individual_trade_screening
      end

      sig { returns(T::Boolean) }
      def entity_trade_screening_validation?
        # for some reason rails puts custom validation context in a Hash, while built in validation
        # context is a symbol. This is only the case because the validation context is being used from the dependency
        return validation_context.dig(:context) == :entity_trade_screening if validation_context.is_a?(Hash)

        validation_context == :entity_trade_screening
      end

      sig { void }
      def valid_for_individual_trade_screening
        details = customer_details

        errors.add(:first_name, details.validate_first_name) if details.validate_first_name.present?
        errors.add(:last_name, details.validate_last_name) if details.validate_last_name.present?
        valid_for_trade_screening(details: details)
      end

      sig { void }
      def valid_for_entity_trade_screening
        details = customer_details

        errors.add(:entity_name, details.validate_entity_name) if details.validate_entity_name.present?
        valid_for_trade_screening(details: details)
      end

      sig { params(details: ::TradeCompliance::TradeScreening::CustomerDetails).void }
      def valid_for_trade_screening(details:)
        errors.add(:address1, details.validate_address1) if details.validate_address1.present?
        errors.add(:address2, details.validate_address2) if details.validate_address2.present?
        errors.add(:city, details.validate_city) if details.validate_city.present?
        errors.add(:country_code, details.validate_country_code) if details.validate_country_code.present?
        errors.add(:postal_code, details.validate_postal_code) if details.validate_postal_code.present?
        errors.add(:region, details.validate_region) if details.validate_region.present?
      end
    end

    sig { returns(String) }
    def trade_screening_request_id
      return id.to_s unless billing?

      # Microsoft requires hardcoded request ID string for billing contacts, while any additional contact types
      # can set whatever request ID they want
      entity_name.present? ? "OrgName_OrgAddr" : "IndName_IndAddr"
    end

    sig { returns(::TradeCompliance::TradeScreening::CustomerDetails) }
    def customer_details
      ::TradeCompliance::TradeScreening::CustomerDetails.new(
        id: trade_screening_request_id,
        first_name: self.first_name,
        last_name: self.last_name,
        entity_name: self.entity_name,
        vat_code: T.must(self.customer).vat_code,
        address1: self.address1,
        address2: self.address2,
        city: self.city,
        region: self.region,
        country_code: self.country_code,
        postal_code: self.postal_code
      )
    end
  end
end
