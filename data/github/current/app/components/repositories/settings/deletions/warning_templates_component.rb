# typed: true
# frozen_string_literal: true

module Repositories
  module Settings
    module Deletions
      class WarningTemplatesComponent < ApplicationComponent
        def initialize(repository:)
          @repository = repository
        end

        private

        attr_reader :repository
      end
    end
  end
end
