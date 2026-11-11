# typed: strict
# frozen_string_literal: true

module DashboardSurface
  module Loaders
    # Shared loader for resolving selected repository filters from search queries.
    # Extracts `repo:owner/name` terms and resolves them to Repository objects
    # for the repo picker UI.
    #
    # This is part of the shared dashboard surface infrastructure.
    class SelectedReposLoader
      MAX_REPOS = 100

      sig { params(query: T.nilable(String), current_user: T.nilable(User)).returns(T::Array[Repository]) }
      def self.from_query(query, current_user)
        return [] if query.blank? || current_user.nil?

        nwos = extract_repo_terms(query).first(MAX_REPOS)
        return [] if nwos.empty?

        resolve_repositories(nwos, current_user)
      rescue => e
        GitHub.logger.warn("SelectedReposLoader.from_query failed: #{e.message}")
        GitHub.dogstats.increment("dashboard_surface.selected_repos.failed")
        Failbot.report(e)
        []
      end

      sig { params(query: String).returns(T::Array[String]) }
      private_class_method def self.extract_repo_terms(query)
        Search::ParsedQuery.parse(query, terms: [:repo]).filter_map do |component|
          component[1] if component.is_a?(Array) && component.first == :repo
        end
      end

      sig { params(nwos: T::Array[String], current_user: User).returns(T::Array[Repository]) }
      private_class_method def self.resolve_repositories(nwos, current_user)
        repositories = Repository.with_names_with_owners(nwos).to_a
        GitHub::PrefillAssociations.prefill_associations(repositories, [:owner])
        repositories.select { |repo| repo.readable_by?(current_user) }
      end
    end
  end
end
