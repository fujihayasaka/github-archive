# typed: true
# frozen_string_literal: true
module Stafftools
  module Models
    class LogoComponent < ApplicationComponent

      sig { params(catalog_item: AzureModels::CatalogItem).void }
      def initialize(catalog_item:)
        @catalog_item = catalog_item
      end

      private

      sig { returns AzureModels::CatalogItem }
      attr_reader :catalog_item

      sig { returns T.nilable(String) }
      def logo_source
        if helpers.color_mode(current_user) == "dark"
          model[:dark_mode_icon]
        else
          model[:light_mode_icon]
        end
      end

      sig { returns String }
      def alt
        model[:name]
      end

      sig { returns T::Hash[T.any(String, Symbol), T.untyped] }
      memoize def model
        catalog_item.parsed_value[:model] || {}
      end
    end
  end
end
