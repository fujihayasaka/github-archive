# frozen_string_literal: true
module Queries
  class AbstractRepositoryDependentsQuery
    include RelayQuery

    delegate :each, to: :results

    NEXT_SLICE = "#{AbstractRepositoryDependency.table_name}.id < ?"
    PREVIOUS_SLICE = "#{AbstractRepositoryDependency.table_name}.id > ?"

    def initialize(depends_on:, limit: 100, github_owner_id: nil)
      @depends_on      = depends_on
      @limit           = limit
      @github_owner_id = github_owner_id
    end

    def results
      return @results if defined?(@results)

      @results = begin
        results = scope
        results = results.where(NEXT_SLICE, @after) if after?
        results = results.where(PREVIOUS_SLICE, @before) if before?

        before? ? results.last(limit) : results.first(limit)
      end
    end

    def dependent_count
      if @github_owner_id
        unordered_scope_without_includes.count
      else
        Views::AbstractRepositoryDependencyCount.for(depends_on)
      end
    end

    def has_previous?
      return false unless results.first.present?

      scope.where(PREVIOUS_SLICE, results.first).exists?
    end

    def has_next?
      return false unless results.last.present?

      scope.where(NEXT_SLICE, results.last).exists?
    end

    private

    attr_reader :depends_on

    def unordered_scope_without_includes
      return @unordered_scope_without_includes if @unordered_scope_without_includes
      abstract_repo_dependencies = AbstractRepositoryDependency
        .use_index("index_abstract_repo_dep_lookups")
        .with_public_repo
        .depends_on(depends_on)
      if @github_owner_id
        abstract_repo_dependencies = abstract_repo_dependencies
          .use_index("index_abstract_repo_dep_uniq_package")
          .repository_owned_by(@github_owner_id)
      end
      @unordered_scope_without_includes = abstract_repo_dependencies
    end

    def scope
      @scope ||= unordered_scope_without_includes.includes(:repository).order(id: :desc)
    end
  end
end
