# typed: true
# frozen_string_literal: true

module GraphQLExtensions
  # Built-in graphql types (like introspection) point to the top-level service
  module MapToServiceForBuiltIns
    def service_mapping(serviceowners: nil)
      :unknown
    end
  end
end
