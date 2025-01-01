# typed: true
# frozen_string_literal: true

class IntegrationInstallation
  # Glues together two complex view models from different domains (repositories
  # and installations) in order to prevent runaway complexity in either
  # controllers or views.
  #
  # Responsible for reshaping the output of repository search/sort queries to
  # be useful in the context of a GitHub App's installation repository access.
  class RepositoryAccessFilter
    attr_reader :installation_show_view, :org_repo_index_view

    # TODO: Yes. I hear you. Delegating this much stuff to two different view
    # models indicates a larger design problem. At the time of writing, this
    # feature is very much in the "exploration" phase and I fully expect a
    # better, more approachable pattern to emerge as more functionality is
    # added. For now, this class is the sin-eater.
    delegate :integration, :installation, :target, :business_installation?, :current_user, :installed_automatically?, :organization_installation?, :repository_installation_required?,
      :installed_on_all_repositories?, :user_installation?, to: :installation_show_view
    delegate :filtering?, :no_repositories?, :phrase, :repositories, :selected_sort_order, :sort_order, :type_filter,
      :organization, :show_new_repository_button?, :show_language_search?, :show_standalone_customize_pinned_repositories?, :type_filter_description, :language, :sort_order_description,
      :type_filters, to: :org_repo_index_view

    def initialize(installation_show_view:, org_repo_index_view:)
      @installation_show_view = installation_show_view
      @org_repo_index_view = org_repo_index_view
    end

    # Public: Repositories associated with a target and whether an
    # installation can access those repositories.
    #
    # Returns an Array of Arrays. Note: Filtering, sorting and pagination has
    # already been done by the the org_repo_index_view object.
    def repositories_with_grant_status
      repositories.map do |repo|
        [repo, granted_access?(repo)]
      end
    end

    private

    def repos_granted_access
      return @granted_on_repos if defined?(@granted_on_repos)
      @granted_on_repos ||= installation.repository_ids(repository_ids: repositories.map(&:id))
    end

    def granted_access?(repo)
      return false if repo.nil?
      repos_granted_access.include?(repo.id)
    end
  end
end
