# typed: true
# frozen_string_literal: true

class Organizations::Settings::DependabotRepositoryAccessFormComponent < ApplicationComponent

  # The dependabot-api enforces a limit on the number of repositories that can
  # be selected for access. This value should match dependabot-api's limit so
  # that the UI limits will be in sync.
  #
  # see https://github.com/github/dependabot-api/blob/main/app/models/repository_access.rb
  MAX_SELECTABLE_REPOS = 250

  def initialize(organization:, selected_repo_ids:, page_param: 1, page_size: 10, max_repos: MAX_SELECTABLE_REPOS)
    @organization = organization
    @selected_repo_ids = selected_repo_ids
    @page_size = page_size
    @max_repos = max_repos
    @page = limit_page(page_param, selected_repo_ids.size, @page_size)
    # preserve original requested page in case it becomes available again
    @orig_page = page_param.to_i
  end

  def limit_page(page_param, repos_count, page_size)
    page = page_param.to_i
    return 1 unless page > 0

    max_page = WillPaginate::Collection.new(page, page_size, repos_count).total_pages
    page < max_page ? page : max_page
  end

  memoize def selected_repositories
    @organization
      .repositories.where(id: @selected_repo_ids.to_a)
      .order(:name)
      .paginate(page: @page, per_page: @page_size, total_entries: selected_repositories_count)
      .to_a
  end

  def internal_repositories_enabled?
    @organization.members_can_create_internal_repositories?
  end

  def autocomplete_hidden?
    selected_repositories.empty?
  end

  def selected_repositories_count
    @selected_repo_ids.size
  end

  def selection_limit_reached?
    selected_repositories_count >= @max_repos
  end

  def show_pagination?
    selected_repositories_count > @page_size
  end

  def pagination_link_params
    {
      controller: "/orgs/dependabot_repository_access",
      action: "show",
      organization_id: @organization.display_login,
      anchor: "dependabot-repository-access",
    }
  end
end
