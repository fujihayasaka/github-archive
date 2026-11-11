# typed: true
# frozen_string_literal: true

module Search
  module Filters

    # Filter to create repository-related ES document fragments in nested groups of Advanced Issues Search.
    # e.g.: (label:bug AND repo:foo/bar) OR (assignee:krhkt AND org:mon-org-alisa)
    #
    # This class was designed to be lighter than RepositoryFilter and to ALWAYS work in conjunction with RepositoryFilter.
    # Searches not scoped to repositories (searches that don't have a set @repo_id) should always use
    # the RepositoryFilter result AND'ed to the ES query document as a first level check. This class
    # is simply responsible for creating the repo_id document fragments nested in complex queries.
    class ConditionalRepositoryFilter < RepositoryFilter
      # When querying against multiple users, using the limits defined in the RepositoryFilter class
      # removes matches from the search results since the ordering differ from
      # the RepositoryFilter class now that public repositories have to be included per owner.
      # However, we're still trying to have a reaseonable upper limit to the amount of repository ids an
      # ownership filter branch can generate.
      MAX_REPOSITORY_IDS_LIMIT = 15_000

      # Constant used to map empty ownership filters to a non-matchable fragment
      INEXISTENT_REPOSITORY_ID = -1

      # Restores blank? method functionality.
      sig { returns(T::Boolean) }
      def blank?
        bool_collection.blank?
      end

      # Restores execution method functionality.
      sig { returns(Symbol) }
      def execution
        options.fetch(:execution, :plain)
      end

      sig { returns(T::Boolean) }
      def and_execution?
        execution == :and
      end

      sig { returns(T::Boolean) }
      def or_execution?
        execution == :or
      end

      # Restores map_bool_collection method functionality.
      sig { returns(::Search::ParsedQuery::BoolCollection) }
      def map_bool_collection
        return bool_collection if defined? @mapped
        @mapped = true

        bool_collection
      end

      # Returns a filter Hash that can be used in the `must` portion of an ES
      # boolean filter.
      def must
        #empty filter should be ignored instead of returning {term: {public: true}} for conditional repositories
        return nil unless bool_collection.must?

        values = bool_collection.must
        must_filters = values.map do |value|
          if value.is_a?(Array)
            { terms: { @field => value } } # when multiple repo_ids satisfy the filter (:org, :user, :owner)
          else
            { term: { @field => value } }
          end
        end
        must_filters
      end

      # Returns a filter Hash that can be used in the `should` portion of an ES
      # boolean filter.
      def should
        return nil unless bool_collection.should?

        values = bool_collection.should
        if values.size > 1
          { terms: { @field => values } }
        else
          { term: { @field => values[0] } }
        end
      end

      sig { returns(::Search::ParsedQuery::BoolCollection) }
      memoize def bool_collection
        @bool_collection = ::Search::ParsedQuery::BoolCollection.new

        return @bool_collection unless repository_scoping_related_qualifiers? && @repo_id.nil?

        repo_ids = {
          must_should: [],
          must_not: [],
        }

        if qualifiers.has_key?(:repo)
          # repo:foo/bar / -repo:baz/qux
          map_repo_name_with_owner_to_repo_ids(qualifiers[:repo], @limit_to_repo_ids) => { must_should_repo_ids:, must_not_repo_ids: }
          repo_ids[:must_should].concat(must_should_repo_ids)
          repo_ids[:must_not].concat(must_not_repo_ids)
        end

        if qualifiers.has_key?(:org)
          # org:foo / -org:bar
          map_users_to_repo_ids(qualifiers[:org], @limit_to_repo_ids) => { must_should_repo_ids:, must_not_repo_ids: }
          repo_ids[:must_should].concat(must_should_repo_ids)
          repo_ids[:must_not].concat(must_not_repo_ids)
        end

        if qualifiers.has_key?(:user)
          # user:baz / -user:qux
          map_users_to_repo_ids(qualifiers[:user], @limit_to_repo_ids) => { must_should_repo_ids:, must_not_repo_ids: }
          repo_ids[:must_should].concat(must_should_repo_ids)
          repo_ids[:must_not].concat(must_not_repo_ids)
        end

        if qualifiers.has_key?(:owner)
          # owner:foo / -owner:baz
          map_users_to_repo_ids(qualifiers[:owner], @limit_to_repo_ids) => { must_should_repo_ids:, must_not_repo_ids: }
          repo_ids[:must_should].concat(must_should_repo_ids)
          repo_ids[:must_not].concat(must_not_repo_ids)
        end

        # prune excluded repositories before applying conditional logic, so that:
        #   (repo:foo/bar -repo:foo/bar repo:bar/baz label:bug)
        # is evaluated as:
        #   (repo:bar/baz label:bug)
        if repo_ids[:must_not].present?
          repo_ids[:must_should] -= repo_ids[:must_not]
          repo_ids.each { |inner| inner -= repo_ids[:must_not] if inner.is_a?(Array) }
        end

        if and_execution?
          # Note: when using an ownership filter with a user or org that doesn't have any repository available,
          # the collection of this filter would be empty, that then would map to no fragment, entirely removing it
          # from the main search query.
          #
          # For instance, suppose that the current search query is:
          #   `(is:closed AND user:steves) OR (label:bug AND org:org-with-no-repo)`
          #
          # And that the org `org-with-no-repo` doesn't have any repositories available
          # at the moment. Then, when generating the ES document, the `org` filter would not be
          # present, making the search query equivalent to:
          #   `(is:closed AND user:steves) OR label:bug`
          # This query then matches issues/prs that belong to other repositories accessible by the current
          # user that have "label:bug". When the desired match should result in:
          #   `(is:closed AND user:steves) OR (label:bug AND _false_)`
          #
          # By adding `{repo_id: INEXISTENT_REPOSITORY_ID}`, we force the generation of a fragment containing a
          # `repo_id` that never matches any document, filtering out the conditional group.
          if should_add_inexistent_repository_id?(repo_ids[:must_should])
            @bool_collection.must(INEXISTENT_REPOSITORY_ID)
          else
            @bool_collection.must(repo_ids[:must_should])
          end
        elsif repo_ids[:must_should].present?
          repo_ids[:must_should].flatten!
          repo_ids[:must_should].uniq!
          @bool_collection.should(repo_ids[:must_should])
        end

        @bool_collection.must_not(repo_ids[:must_not]) unless repo_ids[:must_not].empty?

        @bool_collection
      end

      sig { params(repo_ids: T::Array[T.any(Integer, T::Array[Integer])]).returns(T::Boolean) }
      def should_add_inexistent_repository_id?(repo_ids)
        return false unless must_value_in_qualifiers?
        # If there are no repository IDs, inject an inexistent repository ID to ensure the filter does not match anything.
        return true if repo_ids.empty?
        return false if repo_ids.size == 1

        empty_intersection?(repo_ids)
      end

      def empty_intersection?(repo_ids)
        repo_ids.map { |el| Array(el) }.reduce(&:&).empty?
      end

      sig { returns(T::Boolean) }
      def repository_scoping_related_qualifiers?
        qualifiers.has_key?(:repo) ||
        qualifiers.has_key?(:org) ||
        qualifiers.has_key?(:user) ||
        qualifiers.has_key?(:owner)
      end

      sig { returns(T::Boolean) }
      def must_value_in_qualifiers?
        (qualifiers.has_key?(:repo) && qualifiers[:repo].must.present?) ||
        (qualifiers.has_key?(:org) && qualifiers[:org].must.present?) ||
        (qualifiers.has_key?(:user) && qualifiers[:user].must.present?) ||
        (qualifiers.has_key?(:owner) && qualifiers[:owner].must.present?)
      end

      private

      sig do
        params(
          qualifier: ::Search::ParsedQuery::BoolCollection,
          limit_to_repo_ids: T.nilable(T::Array[Integer]),
        ).returns(T::Hash[Symbol, T.nilable(Array)])
      end
      def map_repo_name_with_owner_to_repo_ids(qualifier, limit_to_repo_ids = [])
        # repo:foo/bar
        repo_nwos = (qualifier.must.presence || []) + (qualifier.should.presence || [])
        repo_nwos.uniq!
        must_should_repo_ids = repository_ids_from_repo(repo_nwos)
        if must_should_repo_ids.present?
          must_should_repo_ids.uniq!
          must_should_repo_ids = must_should_repo_ids - protected_repo_ids
          must_should_repo_ids &= limit_to_repo_ids if limit_to_repo_ids.present?
          must_should_repo_ids.push(INEXISTENT_REPOSITORY_ID) if and_execution? && must_should_repo_ids.size < repo_nwos.size
        end

        # -repo:foo/bar
        must_not_repo_ids = repository_ids_from_repo(qualifier.must_not)
        if must_not_repo_ids.present?
          must_not_repo_ids.flatten!
          must_not_repo_ids.uniq!
        end

        { must_should_repo_ids:, must_not_repo_ids: }
      end

      sig do
        params(
          qualifier: ::Search::ParsedQuery::BoolCollection,
          limit_to_repo_ids: T.nilable(T::Array[Integer]),
        ).returns(T::Hash[Symbol, T.nilable(Array)])
      end
      def map_users_to_repo_ids(qualifier, limit_to_repo_ids = [])
        # [field]:[value]
        user_logins = (qualifier.must.presence || []) + (qualifier.should.presence || [])
        user_logins.uniq!

        # if there are multiple user_logins in an AND context, the resulting arrays
        # for each user would never have an intersection, since the ownership of
        # a repository can't be shared, making the query safe to skip
        if or_execution? || user_logins.size <= 1
          repo_ids = repositories_by_user_logins(user_logins, limit_to_repo_ids:)
          repo_ids = repo_ids - protected_repo_ids unless repo_ids.empty?
          repo_ids = [repo_ids] unless repo_ids.empty?
          must_should_repo_ids = repo_ids
        else
          must_should_repo_ids = [INEXISTENT_REPOSITORY_ID]
        end

        # -[field]:[value]
        must_not_repo_ids = repository_ids_from_user(
          qualifier.must_not,
          limit_to_repo_ids:
        )
        if must_not_repo_ids.present?
          must_not_repo_ids.flatten!
          must_not_repo_ids.uniq!
        end

        { must_should_repo_ids:, must_not_repo_ids: }
      end

      sig do
        params(
          user_logins: T::Array[String],
          limit_to_repo_ids: T.nilable(T::Array[Integer])
        ).returns(T::Array[Integer])
      end
      def repositories_by_user_logins(user_logins, limit_to_repo_ids: nil)
        return [] if user_logins.blank?

        user_ids = searchable_user_ids(user_logins)
        repository_ids = T.let([], T::Array[Integer])
        GH.context.act_as(current_user) do
          repository_ids = ::Repositories.domain.private_repo_ids_by_owner_for_actor(
            owner_id: user_ids,
            resource: @resource,
          )
        end

        remaining_limit = MAX_REPOSITORY_IDS_LIMIT - repository_ids.size
        public_repository_ids = T.let([], T::Array[Integer])
        user_ids.each do |owner_id|
          break if remaining_limit <= 0
          public_repository_ids = ::Repositories.domain.repo_ids_by_owner(
            owner_id:,
            repo_ids_in: nil,
            active_only: true,
            public_only: true,
          )
          remaining_limit -= public_repository_ids.size
          repository_ids.concat(public_repository_ids)
        end

        if remaining_limit <= 0
          GitHub.dogstats.increment(
            "search.query.conditional_repository_filter.hit_max_repo_filter_limit",
            tags: [
              "user_logins:#{user_ids.size}",
              "execution_context:#{execution}"],
          )
        end

        repository_ids &= limit_to_repo_ids if limit_to_repo_ids.present?

        repository_ids.compact!

        repository_ids
      end
    end  # ConditionalRepositoryFilter
  end  # Filters
end  # Search
