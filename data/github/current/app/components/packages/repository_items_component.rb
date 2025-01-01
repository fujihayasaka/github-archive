# typed: true
# frozen_string_literal: true

module Packages
  class RepositoryItemsComponent < ApplicationComponent
    def initialize(next_page:, package:, owner:, repositories:, total_count:)
      @package = package
      @next_page = next_page
      @owner = owner
      @repositories = repositories
      @show_next_page = (next_page - 1) * RegistryTwo::RepositoryItemsController::PER_PAGE < total_count # current page * repos per page < total_count
    end

    def render?
      @show_next_page || @repositories.any?
    end
  end
end
