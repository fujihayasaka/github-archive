# frozen_string_literal: true

module CVEReviewTriage
  class AffectedProductsComponent < ApplicationComponent
    attr_reader :affected_products_payload

    def initialize(affected_products_payload:)
      @affected_products_payload = affected_products_payload
    end

    def affected_products
      affected_products_list = affected_products_payload || []
      ecosystem_package_pairs_seen = {}

      affected_products_list.reduce([]) do |filtered_list, affected_product|
        ecosystem_package_pair = "#{affected_product["ecosystem"]}/#{affected_product["package"]}"

        if ecosystem_package_pairs_seen[ecosystem_package_pair]
          filtered_list
        else
          ecosystem_package_pairs_seen[ecosystem_package_pair] = true
          filtered_list.concat([affected_product.symbolize_keys])
        end
      end
    end
  end
end
