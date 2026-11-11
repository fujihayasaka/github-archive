# typed: strict
# frozen_string_literal: true

module Licensing
  module Licensify
    class LicensifyProduct < T::Enum
      enums do
        SDLC = new
        GHAS = new
        CODE_SECURITY = new
        SECRET_PROTECTION = new
        COPILOT = new
        CODE_QUALITY = new
      end

      sig { returns(Integer) }
      def to_proto
        case self
        when SDLC then ::Licensify::Services::V1::Product::PRODUCT_SDLC
        when GHAS then ::Licensify::Services::V1::Product::PRODUCT_GHAS
        when CODE_SECURITY then ::Licensify::Services::V1::Product::PRODUCT_CODE_SECURITY
        when SECRET_PROTECTION then ::Licensify::Services::V1::Product::PRODUCT_SECRET_PROTECTION
        when COPILOT then ::Licensify::Services::V1::Product::PRODUCT_COPILOT
        when CODE_QUALITY then ::Licensify::Services::V1::Product::PRODUCT_CODE_QUALITY
        end
      end

      sig { returns(String) }
      def to_param
        case self
        when SDLC then "sdlc"
        when GHAS then "ghas"
        when CODE_SECURITY then "code_security"
        when SECRET_PROTECTION then "secret_protection"
        when COPILOT then "copilot"
        when CODE_QUALITY then "code_quality"
        end
      end

      sig { params(sku: GitHub::Turboghas::SKU).returns(LicensifyProduct) }
      def self.from_turboghas_sku(sku)
        case sku
        when GitHub::Turboghas::SKU::Bundled
          LicensifyProduct::GHAS
        when GitHub::Turboghas::SKU::CodeSecurity
          LicensifyProduct::CODE_SECURITY
        when GitHub::Turboghas::SKU::SecretSecurity
          LicensifyProduct::SECRET_PROTECTION
        end
      end

      BUSINESS_LICENSE_PRODUCTS = T.let([
        LicensifyProduct::SDLC,
        LicensifyProduct::GHAS,
        LicensifyProduct::CODE_SECURITY,
        LicensifyProduct::SECRET_PROTECTION,
        LicensifyProduct::COPILOT,
        LicensifyProduct::CODE_QUALITY,
      ].freeze, T::Array[LicensifyProduct])

      ORGANIZATION_LICENSE_PRODUCTS = T.let([
        LicensifyProduct::SDLC,
        LicensifyProduct::CODE_SECURITY,
        LicensifyProduct::SECRET_PROTECTION,
        LicensifyProduct::COPILOT,
        LicensifyProduct::CODE_QUALITY,
      ].freeze, T::Array[LicensifyProduct])

      sig { params(entity: Billing::Types::Account).returns(T::Array[String]) }
      def self.for(entity)
        products = entity.is_a?(Business) ? BUSINESS_LICENSE_PRODUCTS : ORGANIZATION_LICENSE_PRODUCTS

        products.map(&:to_param)
      end
    end
  end
end
