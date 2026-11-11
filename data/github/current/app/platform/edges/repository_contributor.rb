# typed: true
# frozen_string_literal: true

module Platform
  module Edges
    class RepositoryContributor < Edges::Base
      description "A user who has contributed to a repository."
      minimum_accepted_scopes ["public_repo"]
      required_capabilities [:mobile_only_schema_mask]

      # Since in this case, the `node` isn't actually `object.node`,
      # override this to pass along the user instead.
      def self.authorized?(object, context)
        user = object.node.user
        Objects::User.authorized?(user, context)
      end

      node_type Objects::User

      def node
        @object.node.user
      end

      field :contributions_count, Integer,
        description: "The number of contributions the user has made in the repository.", null: false

      def contributions_count
        @object.node.contributions_count
      end
    end
  end
end
