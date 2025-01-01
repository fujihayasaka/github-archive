# typed: true
# frozen_string_literal: true

module Packages
  class RepositorySearchComponent < ApplicationComponent
    def initialize(package:, owner:, repositories:)
      @package = package
      @owner = owner
      @repositories = repositories
    end
  end
end
