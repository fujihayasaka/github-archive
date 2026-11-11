# typed: strict
# frozen_string_literal: true

module ContextRegion
  class MarketplaceCrumb < Crumb
    sig { override.returns(String) }
    def label
      "Marketplace"
    end

    sig { override.returns(T.nilable(Symbol)) }
    def path_name
      :marketplace_path
    end
  end
end
