# typed: true
# frozen_string_literal: true

module ContextRegion
  module Marketplace
    class ActionsCrumb < Crumb
      sig { returns String }
      def label
        "Actions"
      end

      sig { returns Symbol }
      def path_name
        :marketplace_actions_path
      end

      sig { override.returns(MarketplaceCrumb) }
      def parent
        MarketplaceCrumb.new
      end
    end
  end
end
