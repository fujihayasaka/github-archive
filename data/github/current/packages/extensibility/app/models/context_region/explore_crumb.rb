# typed: true
# frozen_string_literal: true

module ContextRegion
  class ExploreCrumb < Crumb
    def label
      "Explore"
    end

    def path_name
      :explore_path
    end
  end
end
