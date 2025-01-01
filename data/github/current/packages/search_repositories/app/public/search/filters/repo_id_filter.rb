# typed: strict
# frozen_string_literal: true

module Search
  module Filters
    # A filter that restrict search results to the array of repo IDs provided.
    #
    class RepoIdFilter < ::Search::Filter
      extend T::Sig

      FilterHash = T.type_alias { T::Hash[Symbol, T.untyped] }
      FilterHashResult = T.type_alias { T.any(FilterHash, T::Array[FilterHash]) }

      # Create a new RepoIdFilter instance using the given options.
      #   field         - The field name for the repo ID that this filter operates on
      #   repo_ids      - The Array of repo IDs to filter on
      #   also_public   - Include public repositories in the filter
      #   also_internal - Include internal repositories in the filter
      #
      sig do
        params(
          field: Symbol,
          repo_ids: T::Array[Integer],
          also_public: T::Boolean,
          also_internal: T::Boolean,
        ).void
      end
      def initialize(field, repo_ids, also_public: false, also_internal: false)
        super({ field: })

        @repo_ids = repo_ids
        @also_public = also_public
        @also_internal = also_internal
      end

      sig { returns(FilterHashResult) }
      def must
        visibility_values = []
        visibility_values << "public" if @also_public
        visibility_values << "internal" if @also_internal

        should_clauses = [build_term_filter(field, @repo_ids), build_term_filter(:visibility, visibility_values)]
        should_clauses.compact!

        return { terms: { field => [] } } if should_clauses.empty?

        return should_clauses.first if should_clauses.size == 1

        { bool: { should: should_clauses } }
      end

      # This filter cannot be blank, we always must apply it to avoid leaking other repos
      sig { returns(T::Boolean) }
      def blank?
        false
      end

      # This filter is global when it has no repo_ids, as the visibility filters are not constraining enough
      sig { returns(T::Boolean) }
      def global?
        @repo_ids.empty?
      end

      # Validates whether the given repo is accessible by current user,
      # checking also the cap filter for the business authorization
      sig { params(repo: Repository).returns(T::Boolean) }
      def accessible_repository?(repo)
        @repo_ids.include?(repo.id) || (@also_public && repo.public?) || (@also_internal && repo.internal?)
      end
    end
  end
end
