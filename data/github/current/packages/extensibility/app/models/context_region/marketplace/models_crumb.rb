# typed: strict
# frozen_string_literal: true

module ContextRegion
  module Marketplace
    class ModelsCrumb < Crumb
      sig { override.returns(String) }
      def label
        "Models"
      end

      sig { override.returns(T.nilable(Symbol)) }
      def path_name
        :marketplace_models_catalog_path
      end

      sig { override.returns(Crumb) }
      def parent
        MarketplaceCrumb.new
      end
    end
  end
end
