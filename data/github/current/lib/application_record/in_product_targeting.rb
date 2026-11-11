# typed: true
# frozen_string_literal: true

module ApplicationRecord
  class InProductTargeting < Base
    self.abstract_class = true

    connects_to database: { writing: :in_product_targeting_primary, reading: :in_product_targeting_readonly }

    def self.production_schema_name
      "in_product_targeting"
    end
  end
end
