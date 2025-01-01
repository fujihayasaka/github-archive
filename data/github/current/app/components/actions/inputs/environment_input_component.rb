# typed: true
# frozen_string_literal: true

module Actions
  module Inputs
    class EnvironmentInputComponent < ApplicationComponent
      def initialize(input:, id:, current_repository:)
        @input = input
        @id = id
        @current_repository = current_repository
      end

      def call
        render(Actions::Inputs::DropdownInputComponent.new(input: @input, id: @id, options: options))
      end

      private

      memoize def options
        @current_repository.environments.pluck(:name)
      end
    end
  end
end
