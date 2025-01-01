# typed: strict
# frozen_string_literal: true

module Search
  module Queries
    # This class is used by Search::Queries::MemexProjectItemQuery to redact Elasticsearch results based on repositories within the project.
    #
    class MemexProjectItemQueryRedactor
      extend T::Sig

      # The maximum number of repository IDs that can be used for repository aggregation and redacted respository item filtering.
      # It would be exceedingly rare for a Memex project to contain items referencing more than a handful of repositories.
      # This is the same as the maximum number of repository IDs that can be used for filtering in the general RepositoryFilter.
      # https://github.com/github/github/blob/741876a15ad155bbe01301f3d142f2ea91551755/packages/search/app/models/search/filters/repository_filter.rb#L21C10-L21C10
      MAX_REPO_FILTER_SIZE = 4_000

      # Initializes a MemexProjectItemQueryRedactor used to redact Elasticsearch results based on repositories within the project.
      #
      # @param viewer Optional User for whom results should be authorized. `nil`, the default, represents an
      #   anonymous user (e.g. viewing a public project when logged out).
      # @param cap_filter: Optional filter to satisfy conditional access policies for items referencing issues in SSO orgs.
      sig do
        params(
          viewer: T.nilable(User),
          cap_filter: T.nilable(ConditionalAccess::Filter),
        )
        .void
      end
      def initialize(
          viewer: nil,
          cap_filter: nil
        )
        @current_user = viewer
        @cap_filter = cap_filter
        @authorized_repo_ids = T.let(nil, T.nilable(T::Array[Numeric]))
      end


      # Returns true if this is the second query execution that includes a filter for visible repositories.
      sig { returns(T::Boolean) }
      def query_has_redacted_repo_ids?
        !@authorized_repo_ids.nil?
      end

      # Check if the user is authorized to view all of the item repositories returned by the first query.
      # If not, then return true to indicate that a requery is required with a filter on the repositories visible to the user.
      sig do
        params(
          response: T.any(Search::Responses::MemexProjectItemResponse, Search::Responses::GroupedMemexProjectItemResponse),
          prefilled_repositories: T::Array[Repository]
        )
        .returns(T::Boolean)
      end
      def requires_requery_for_redactions?(response, prefilled_repositories: [])
        # return false if this is already the second query execution
        return false if query_has_redacted_repo_ids?

        queried_repo_ids = response.repository_ids
        authorized_repo_ids = MemexProjectRepositoryRedactor.new(
             cap_filter: @cap_filter,
             user: @current_user,
             repo_ids: queried_repo_ids,
             prefilled_repositories:
        ).authorized_repo_ids

        if queried_repo_ids.length > authorized_repo_ids.length
          @authorized_repo_ids = authorized_repo_ids
          true
        else
          false
        end
      end

      # The repositories_aggregation is added to the first query to return all repositories referenced in the project.
      # These are used to determine if a second query with a filter for visible repositories is required.
      sig { params(key_prefix: String).returns(Elastomer::Interfaces::Api::Search::Request::Aggregation::Terms) }
      def repositories_aggregation(key_prefix: "")
        Elastomer::Interfaces::Api::Search::Request::Aggregation::Terms.new(
          slug: "#{key_prefix}repository_ids".to_sym,
          field: "content.repository_id",
          size: MAX_REPO_FILTER_SIZE
        )
      end

      # The repository_ids_query_fragment is added to the second query to filter on repositories visible to the user.
      # This is only required if the first query returns any repositories that are not visible to the user.
      sig { returns(T::Hash[T.untyped, T.untyped]) }
      def repository_ids_query_fragment
        {
          bool: {
            should: [
              # Issues and PRs: filter on repositories visible to the user
              { terms: { "content.repository_id": @authorized_repo_ids } },
              # Draft issues: these have no repository and are always visible to the user
              { term: { "content.type": "DraftIssue" } },
            ],
            minimum_should_match: 1
          }
        }
      end
    end
  end
end
