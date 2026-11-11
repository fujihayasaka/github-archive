# typed: strict
# frozen_string_literal: true

module ContextRegion
  class ExploreCrumb < Crumb
    sig { override.returns(String) }
    def label
      "Explore"
    end

    sig { override.returns(T.nilable(Symbol)) }
    def path_name
      :explore_path
    end
  end
end
