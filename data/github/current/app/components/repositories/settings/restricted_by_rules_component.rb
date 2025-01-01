# typed: true
# frozen_string_literal: true

module Repositories
  module Settings
    class RestrictedByRulesComponent < ApplicationComponent
      def initialize(rules_provider:, test_selector:)
        @rules_provider = rules_provider
        @test_selector = test_selector
      end
    end
  end
end
