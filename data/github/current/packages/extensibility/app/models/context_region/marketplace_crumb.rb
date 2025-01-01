# typed: true
# frozen_string_literal: true

module ContextRegion
  class MarketplaceCrumb < Crumb
    def label
      "Marketplace"
    end

    def path_name
      :marketplace_path
    end
  end
end
