# typed: true
# frozen_string_literal: true

module Platform
  module Connections
    class RepositoryContributor < Connections::Base
      minimum_accepted_scopes ["public_repo"]
      required_capabilities [:mobile_only_schema_mask]

      total_count_field description: <<~DESCRIPTION
        Identifies the total count of contributors to this repository.
      DESCRIPTION

      def total_count
        CommitContributions.domain.contributors_count_for_repository(@object.parent)
      end

      def nodes
        @object.edge_nodes.map do |user_contribution|
          if user_contribution.is_a? CommitContribution
            user_contribution.async_user
          else
            user_contribution.user
          end
        end
      end
    end
  end
end
