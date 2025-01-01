# typed: true
# frozen_string_literal: true

module Stafftools
  module Explore
    class BaseComponent < ApplicationComponent # rubocop:disable ViewComponent/ComponentsHaveUnitTests
      CONTEXTS        = [:stafftools, :biztools]
      DEFAULT_CONTEXT = :stafftools

      def initialize(context:)
        @context = fetch_or_fallback(CONTEXTS, context, DEFAULT_CONTEXT)
      end

      private

      attr_reader :context

      def stafftools?
        context == :stafftools
      end

      def biztools?
        context == :biztools
      end
    end
  end
end
