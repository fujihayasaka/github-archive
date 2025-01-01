# typed: true
# frozen_string_literal: true
module Memex
  class UserProjectsNavigationComponent < ApplicationComponent
    def initialize(query_contains_beta:, beta_path:, classic_path:)
      @query_contains_beta = query_contains_beta
      @beta_path = beta_path
      @classic_path = classic_path
    end

    memoize def views
      {
        new: [@beta_path, "Projects", :new, :table],
        classic: [@classic_path, "Projects (classic)", :classic, :project],
      }
    end

    memoize def selected_item_id
      @query_contains_beta ? :new : :classic
    end
  end
end
