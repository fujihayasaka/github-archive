# typed: strict
# frozen_string_literal: true

module Copilot
  module Purchase
    class CheckoutSectionComponent < ApplicationComponent

      renders_one :subheading
      renders_one :children
      renders_one :footer

      sig { returns(String) }
      attr_accessor :heading, :heading_link

      sig { params(heading: String, heading_link: String, visible: T::Boolean).void }
      def initialize(heading: "", heading_link: "", visible: true)
        @heading = heading
        @heading_link = heading_link
        @visible = visible
      end

      sig { returns(T::Boolean) }
      def render?
        @visible
      end
    end
  end
end
