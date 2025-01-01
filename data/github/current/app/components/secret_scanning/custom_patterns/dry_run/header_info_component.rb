# typed: strict
# frozen_string_literal: true

module SecretScanning
  module CustomPatterns
    module DryRun
      class HeaderInfoComponent < ApplicationComponent # rubocop:disable ViewComponent/ComponentsHaveUnitTests
        extend T::Sig

        sig { returns(String) }
        attr_reader :heading, :value

        sig { returns(T::Boolean) }
        attr_reader :show_danger_text

        sig { params(heading: String, value: String, show_danger_text: T::Boolean).void }
        def initialize(heading:, value:, show_danger_text:)
          @heading = heading
          @value = value
          @show_danger_text = show_danger_text
        end
      end
    end
  end
end
