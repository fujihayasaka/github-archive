# typed: strict
# frozen_string_literal: true

module Planning
  class Domain < GH::Domain::Base
    include GitHub::ResilienceMixin

    # Cached version of repository#open_memex_projects_count_for
    # TODO: remove #open_memex_projects_count_for from Repository and implement the method
    # here instead, downgrading to non-AR arguments
    sig { params(repository: ::Repository, viewer: T.nilable(::User)).returns(Numeric) }
    def open_memex_projects_count_for_repo(repository, viewer)
      any_memex_links = with_database_error_fallback do
        repository.memex_project_links.any?
      end

      return 0 if any_memex_links.nil? || !any_memex_links

      Memex::Cache::OpenMemexProjectsCountClient.new(repository, viewer).fetch do
        repository.memex_projects_scope_for(viewer).open_projects.count
      end
    end
  end
end
