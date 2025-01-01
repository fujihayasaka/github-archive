# typed: true
# frozen_string_literal: true

module ContextRegion
  module Marketplace
    class AppsCrumb < Crumb
      sig { returns String }
      def label
        "Apps"
      end

      sig { returns Symbol }
      def path_name
        :marketplace_path
      end

      sig { returns(T::Array[T::Hash[Symbol, String]]) }
      def path_args
        [{
          type: "apps",
        }]
      end

      sig { override.returns(MarketplaceCrumb) }
      def parent
        MarketplaceCrumb.new
      end
    end
  end
end
