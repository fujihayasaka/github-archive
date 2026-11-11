# typed: strict
# frozen_string_literal: true

module ControlGroup
  module Item
    class LeadingIconComponent < ApplicationComponent
      sig { params(icon: String, size: Symbol).void }
      def initialize(icon:, size: :small)
        @icon = icon
        @size = size
      end

      sig { returns(String) }
      def call
        render(Primer::Beta::Octicon.new(icon: @icon, size: @size))
      end
    end
  end
end
