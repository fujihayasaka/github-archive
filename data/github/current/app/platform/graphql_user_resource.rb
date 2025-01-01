# typed: true
# frozen_string_literal: true

module Platform
  # An object representing a resource that is owned by
  # a user but attempting to be accessed by a GitHub App.
  # This can be passed to control_access when no other handy
  # object is available, specifically in a GraphQL context.
  class GraphqlUserResource
    attr_reader :permissions
    def initialize(permissions:)
      @permissions = permissions
    end

    def readable_by?(_)
      true
    end
  end
end
