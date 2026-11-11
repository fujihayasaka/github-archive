# typed: true
# frozen_string_literal: true

module Platform
  module Helpers
    module InternalGraphql
      # Is this query executing from the InternalGraphqlController supporting a
      # frontend internal app?
      def self.internal_graphql?(context)
        context.key?(:is_internal_graphql)
      end
    end
  end
end
