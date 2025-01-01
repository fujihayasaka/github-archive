# typed: true
# frozen_string_literal: true

module Platform
  module Tracing
    module NullTracer
      include GraphQL::Tracing::NullTracer

      def platform_execute
        yield
      end
    end
  end
end
