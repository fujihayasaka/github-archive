# typed: strict
# frozen_string_literal: true

module Search
  module Queries
    # This class is used by Search::Queries::MemexProjectItemQuery to redact Elasticsearch results for authorization and spam.
    # It provides aggregation fragments to add to the Elasticsearch query to subsequently check the response for redactions.
    # If it has redactions, then it provides filter fragments to add to a second Elasticsearch query to limit results in the response.
    #
    # EXAMPLE:
    #
    #   Basic overview of usage, with <aggregations> and <filters> as parts of the query for Elasticsearch:
    #
    #   project_item_query = MemexProjectItemQuery.new(params)
    #   redactor = MemexProjectItemQueryRedactor.new(viewer:, cap_filter:)
    #   project_item_query.<aggregations>.merge(redactor.redactions_aggregations)
    #   response = project_item_query.execute
    #   redactor.check_for_redactions(response, prefilled_repositories:)
    #   if redactor.has_redactions?
    #     project_item_query.<filters>.merge(redactor.redactions_query_fragment)
    #     response = project_item_query.execute
    class MemexProjectItemQueryRedactor

      class Results < T::Struct
        # Repository ids that were authorized for viewing by the current user, including CAP.
        const :authorized_repo_ids, T::Array[Integer]
        # Repository ids that were checked but found to be not authorized for viewing by the current user.
        # These could include explicitly forbidden repositories or repositories that failed CAP checks.
        const :unauthorized_repo_ids, T::Array[Integer]
        # True if the response was checked for spammy items, if applicable.
        const :checked_for_spam, T::Boolean
      end

      # The maximum number of repository IDs that can be used for repository aggregation and redacted respository item filtering.
      # It would be exceedingly rare for a Memex project to contain items referencing more than a handful of repositories.
      # This is the same as the maximum number of repository IDs that can be used for filtering in the general RepositoryFilter.
      # https://github.com/github/github/blob/741876a15ad155bbe01301f3d142f2ea91551755/packages/search/app/models/search/filters/repository_filter.rb#L21C10-L21C10
      MAX_REPO_FILTER_SIZE = 4_000
      MAX_CREATOR_FILTER_SIZE = 4_000

      # Redactor results including repository ids that were explicitly checked for authorization (Authzd and CAP checks)
      sig { returns(T.nilable(Results)) }
      attr_reader :results

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
        @authorized_repo_ids = T.let([], T::Array[Integer])
        @unauthorized_repo_ids = T.let([], T::Array[Integer])

        @authorized_item_repo_ids = T.let([], T::Array[Integer])
        @unauthorized_item_repo_ids = T.let([], T::Array[Integer])
        @unauthorized_field_repo_ids = T.let([], T::Array[Integer])

        @spammy_item_creator_ids = T.let(nil, T.nilable(T::Array[Integer]))
        @spammy_content_creator_ids = T.let(nil, T.nilable(T::Array[Integer]))
        @has_checked_for_redactions = T.let(false, T::Boolean)
        @results = T.let(nil, T.nilable(Results))
      end

      # Returns true if an Elasticsearch response was checked for auth and spammy redactions.
      sig { returns(T::Boolean) }
      def has_checked_for_redactions?
        @has_checked_for_redactions
      end

      # Returns true if an Elasticsearch response was found to require auth or spammy item redactions.
      sig { returns(T::Boolean) }
      def has_redactions?
        has_unauthorized_item_repo_ids? || has_spammy_creator_ids?
      end

      # Returns true if an Elasticsearch response was found to require aggregated field redactions.
      # For example, if grouping on a parent issue that is in a different, inaccessible repository.
      sig { returns(T::Boolean) }
      def has_field_redactions?
        has_unauthorized_field_repo_ids?
      end

      # Perform authorization and spammy checks on the Elasticsearch response.
      # Subsequently call has_redactions? to determine if a requery with redactions is required.
      sig do
        params(
          response: T.any(Search::Responses::MemexProjectItemResponse, Search::Responses::GroupedMemexProjectItemResponse),
          aggregation_options: MemexProjectItemQuery::AggregationOptions,
          prefilled_repositories: T::Array[Repository]
        ).void
      end
      def check_for_redactions(response:, aggregation_options:, prefilled_repositories: [])

        item_repo_ids = response.repository_ids
        field_repo_ids = T.let([], T::Array[Integer])

        group_options = aggregation_options.grouping_options
        if group_options.present? && response.grouped?
          group_response = T.cast(response, Search::Responses::GroupedMemexProjectItemResponse)
          field_repo_ids += group_options.field.redactable_group_repo_ids(response: group_response, options: group_options)
        end

        slice_by_field = aggregation_options.slice_by_field
        if slice_by_field.present? && response.sliced?
          field_repo_ids += slice_by_field.redactable_slice_repo_ids(response:)
        end

        chart_options = aggregation_options.chart_options
        # TODO chart x-axis field checks.

        check_for_unauthorized_items(item_repo_ids:, field_repo_ids:, prefilled_repositories:)
        check_for_spammy_items(response) if perform_spammy_redactions?
        @has_checked_for_redactions = true
        @results = Results.new(
          authorized_repo_ids: @authorized_repo_ids,
          unauthorized_repo_ids: @unauthorized_repo_ids,
          checked_for_spam: memex_mwl_spam_redaction_enabled?
        )
      end

      # Redactions aggregations are added to the first query to return all repositories and creators referenced in the project.
      # These are used to determine if a second query is required with a filter for visible repositories and/or to exclude spammy items.
      sig { params(key_prefix: String).returns(Elastomer::Interfaces::Api::Search::Request::Aggregation::Collection) }
      def redactions_aggregations(key_prefix: "")
        aggregations = Elastomer::Interfaces::Api::Search::Request::Aggregation::Collection.new([repositories_aggregation(key_prefix:)])
        aggregations.concat(creators_aggregations(key_prefix:)) if perform_spammy_redactions?
        aggregations
      end

      # The redactions_query_fragment is added to the second query to filter on authorized repositories and/or to exclude spammy items.
      # This is only required if this redactor.has_redactions? after processing the first query response.
      sig { returns(T::Array[T::Hash[T.untyped, T.untyped]]) }
      def redactions_query_fragment
        fragments = []
        fragments << repository_ids_query_fragment if has_unauthorized_item_repo_ids?
        fragments << creator_ids_query_fragment if has_spammy_creator_ids?
        fragments
      end

      # Returns true if the memex_mwl_spam_redaction feature flag is enabled.
      # This implies spammy redactions should occur as a second Elasticsearch query rather than filtering a page of fetched items.
      sig { returns(T::Boolean) }
      def memex_mwl_spam_redaction_enabled?
        @current_user.present? ? @current_user.feature_enabled?(:memex_mwl_spam_redaction) : GitHub.flipper[:memex_mwl_spam_redaction].enabled?
      end

      sig { returns(T::Boolean) }
      private def has_unauthorized_item_repo_ids?
        @unauthorized_item_repo_ids.present?
      end

      sig { returns(T::Boolean) }
      private def has_unauthorized_field_repo_ids?
        @unauthorized_field_repo_ids.present?
      end

      sig { returns(T::Boolean) }
      private def has_spammy_creator_ids?
        @spammy_item_creator_ids.present? || @spammy_content_creator_ids.present?
      end

      # Returns true if we should check for and redact any spammy items.
      sig { returns(T::Boolean) }
      private def perform_spammy_redactions?
        spammy_checks_apply = T.let(GitHub.spamminess_check_enabled? && !@current_user&.site_admin?, T::Boolean)
        spammy_checks_apply && memex_mwl_spam_redaction_enabled?
      end

      # The repositories_aggregation is added to the first query to return all repositories referenced in the project.
      # These are used to determine if a second query with a filter for visible repositories is required.
      sig { params(key_prefix: String).returns(Elastomer::Interfaces::Api::Search::Request::Aggregation::Terms) }
      private def repositories_aggregation(key_prefix:)
        Elastomer::Interfaces::Api::Search::Request::Aggregation::Terms.new(
          slug: "#{key_prefix}repository_ids".to_sym,
          field: "content.repository_id",
          size: MAX_REPO_FILTER_SIZE
        )
      end

      # The creators_aggregation is added to the first query to return all item/issue/pr creators referenced in the project.
      # These are used to determine if a second query with a filter to exclude spammy items is required.
      sig { params(key_prefix: String).returns(Elastomer::Interfaces::Api::Search::Request::Aggregation::Collection) }
      private def creators_aggregations(key_prefix:)
        item_creators_agg = Elastomer::Interfaces::Api::Search::Request::Aggregation::Terms.new(
          slug: "#{key_prefix}item_creator_ids".to_sym,
          field: "creator_id",
          size: MAX_CREATOR_FILTER_SIZE
        )
        content_creator_agg = Elastomer::Interfaces::Api::Search::Request::Aggregation::Terms.new(
          slug: "#{key_prefix}content_creator_ids".to_sym,
          field: "content.user_id",
          size: MAX_CREATOR_FILTER_SIZE
        )

        Elastomer::Interfaces::Api::Search::Request::Aggregation::Collection.new([item_creators_agg, content_creator_agg])
      end

      # The repository_ids_query_fragment is added to the second query to filter on repositories visible to the user.
      # This is only required if the first query returns any repositories that are not visible to the user.
      sig { returns(T::Hash[T.untyped, T.untyped]) }
      private def repository_ids_query_fragment
        {
          bool: {
            should: [
              # Issues and PRs: filter on repositories visible to the user
              { terms: { "content.repository_id": @authorized_item_repo_ids } },
              # Draft issues: these have no repository and are always visible to the user
              { term: { "content.type": "DraftIssue" } },
            ],
            minimum_should_match: 1
          }
        }
      end

      # The creator_ids_query_fragment is added to the second query to remove spammy items not visible to the user.
      # Items are spammy if either the item or the issue/pr was created by a spammy user (other than the current viewer).
      sig { returns(T::Hash[T.untyped, T.untyped]) }
      private def creator_ids_query_fragment
        terms = []
        terms.append({ terms: { "creator_id": @spammy_item_creator_ids } }) if @spammy_item_creator_ids.present?
        terms.append({ terms: { "content.user_id": @spammy_content_creator_ids } }) if @spammy_content_creator_ids.present?
        {
          bool: { must_not: terms }
        }
      end

      # Perform authorization checks to determine if the user is allowed to view all of the item repositories in the response.
      # Unauthorized items require a requery with a filter for visible repositories.
      sig do
        params(
          item_repo_ids: T::Array[Integer],
          field_repo_ids: T::Array[Integer],
          prefilled_repositories: T::Array[Repository]
        ).void
      end
      private def check_for_unauthorized_items(item_repo_ids:, field_repo_ids:, prefilled_repositories: [])
        @authorized_item_repo_ids = []
        @unauthorized_item_repo_ids = []
        @unauthorized_field_repo_ids = []
        @authorized_repo_ids = []
        @unauthorized_repo_ids = []
        queried_repo_ids = (item_repo_ids + field_repo_ids).uniq
        return unless queried_repo_ids.present?

        @authorized_repo_ids = MemexProjectRepositoryRedactor.new(
             cap_filter: @cap_filter,
             user: @current_user,
             repo_ids: queried_repo_ids,
             prefilled_repositories:
        ).authorized_repo_ids

        if @authorized_repo_ids.length < queried_repo_ids.length
          @unauthorized_repo_ids = queried_repo_ids - @authorized_repo_ids
          @authorized_item_repo_ids = @authorized_repo_ids.intersection(item_repo_ids)
          @unauthorized_item_repo_ids = item_repo_ids - @authorized_item_repo_ids
          authorized_field_repo_ids = @authorized_repo_ids.intersection(field_repo_ids)
          @unauthorized_field_repo_ids = field_repo_ids - authorized_field_repo_ids
        else
          @authorized_item_repo_ids = item_repo_ids
        end
      end

      # Perform spammy checks to determine if any of the item or content creators in the response are spammy users.
      sig { params(response: T.any(Search::Responses::MemexProjectItemResponse, Search::Responses::GroupedMemexProjectItemResponse)).void }
      private def check_for_spammy_items(response)
        item_creator_ids = response.item_creator_ids
        content_creator_ids = response.content_creator_ids
        creator_ids = (item_creator_ids + content_creator_ids).uniq

        # Spammy users are allowed to view their own spammy items (i.e., items or content they created)
        creators = User.where(id: creator_ids).select(:id, :spammy)
        spammy_creator_ids = creators.filter { _1.spammy && _1.id != @current_user&.id }.map { _1.id }

        if spammy_creator_ids.present?
          @spammy_item_creator_ids = item_creator_ids.intersection(spammy_creator_ids)
          @spammy_content_creator_ids = content_creator_ids.intersection(spammy_creator_ids)
        end
      end
    end
  end
end
