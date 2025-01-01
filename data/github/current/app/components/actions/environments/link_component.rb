# typed: true
# frozen_string_literal: true

module Actions
  module Environments
    class LinkComponent < ApplicationComponent

      def initialize(repository:, environments:)
        @repository = repository
        @environments = environments.uniq
      end

      def render?
        @environments.any?
      end
    end
  end
end
