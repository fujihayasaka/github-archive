# typed: strict
# frozen_string_literal: true

module ApplicationRecord
  class SecurityProductsEnablement < Base
    self.abstract_class = true

    connects_to database: {
      writing: :security_products_enablement_primary,
      reading: :security_products_enablement_readonly,
    }

    sig { returns(Symbol) }
    def self.cluster_name
      :"security-products-enablement"
    end

    sig { returns(String) }
    def self.production_schema_name
      "security_products_enablement"
    end
  end
end
