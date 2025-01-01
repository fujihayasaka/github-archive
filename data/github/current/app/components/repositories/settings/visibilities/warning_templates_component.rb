# typed: true
# frozen_string_literal: true

module Repositories
  module Settings
    module Visibilities
      class WarningTemplatesComponent < ApplicationComponent
        def initialize(repository:, new_visibility:)
          @repository = repository
          @new_visibility = new_visibility
        end

        private

        attr_reader :repository, :new_visibility
      end
    end
  end
end
