# typed: true
# frozen_string_literal: true

module SecretScanning
  module CustomPatterns
    class PostProcessingComponent < ApplicationComponent # rubocop:disable ViewComponent/ComponentsHaveUnitTests
      attr_reader :form, :value, :index, :match, :disable

      def initialize(form:, value:, index:, match:, disabled:)
        @form = form
        @value = value
        @index = index
        @match = match
        @disabled = disable
      end
    end
  end
end
