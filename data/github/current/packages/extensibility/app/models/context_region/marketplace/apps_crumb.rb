# typed: strict
# frozen_string_literal: true

module ContextRegion
  module Marketplace
    class AppsCrumb < Crumb
      sig { override.returns(String) }
      def label
        "Apps"
      end

      sig { override.returns(T.nilable(Symbol)) }
      def path_name
        :marketplace_path
      end

      sig { override.returns(T::Array[T.untyped]) }
      def path_args
        [{
          type: "apps",
        }]
      end

      sig { override.returns(Crumb) }
      def parent
        MarketplaceCrumb.new
      end
    end
  end
end
