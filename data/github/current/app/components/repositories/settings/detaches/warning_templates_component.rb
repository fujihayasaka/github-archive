# typed: true
# frozen_string_literal: true

# tests are here: test/components/repositories/settings/detaches/warning_templates_component_test.rb
module Repositories
  module Settings
    module Detaches
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
