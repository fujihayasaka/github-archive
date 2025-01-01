# typed: true
# frozen_string_literal: true

module ContextRegion
  module Marketplace
    class ModelsCrumb < Crumb
      sig { returns String }
      def label
        "Models"
      end

      sig { returns Symbol }
      def path_name
        :marketplace_models_catalog_path
      end

      sig { override.returns(MarketplaceCrumb) }
      def parent
        MarketplaceCrumb.new
      end
    end
  end
end
