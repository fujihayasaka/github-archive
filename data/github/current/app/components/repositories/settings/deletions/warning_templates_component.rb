# typed: true
# frozen_string_literal: true

module Repositories
  module Settings
    module Deletions
      class WarningTemplatesComponent < ApplicationComponent
        def initialize(repository:, can_request_bypass: false)
          @repository = repository
          @can_request_bypass = can_request_bypass
        end

        private

        attr_reader :repository, :can_request_bypass
      end
    end
  end
end
