# typed: true
# frozen_string_literal: true

module Packages
  class RepositorySearchResultsComponent < ApplicationComponent
    def initialize(repositories:)
      @repositories = repositories
    end
  end
end
