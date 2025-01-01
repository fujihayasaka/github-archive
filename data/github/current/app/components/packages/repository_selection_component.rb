# typed: true
# frozen_string_literal: true

module Packages
  class RepositorySelectionComponent < ApplicationComponent
    def initialize(package:, owner:, repositories:, discard_changes_on_close: false)
      @package = package
      @owner = owner
      @repositories = repositories
      @discard_changes_on_close = discard_changes_on_close
    end
  end
end
