# typed: false
# frozen_string_literal: true

module DashboardSidebarHelper
  DEFAULT_REPOSITORY_SCOPE = "All repositories"
  REPO_AVATAR_SIZE = 16

  # Public: Whether the user has any pinnable repositories.
  # @return [Boolean]
  def any_pinnable_repos?
    current_user.any_pinnable_items?(types: ["Repository"], internal_view: true)
  end

  # Public: Whether the user has any pinned repositories.
  # @return [Boolean]
  def any_pinned_repos?
    current_user.any_dashboard_pinned_items?(
      types: ["Repository"],
      excluded_account_ids: [],
      preload_scope: { pinned_item: :owner }
    )
  end

  # Public: Returns all the pinned repositories for the current user.
  # @return [Array<UserDashboardPin>]
  def all_pinned_items
    current_user.dashboard_pinned_items(
      viewer: current_user,
      types: ["Repository"],
      preload_scope: { pinned_item: :owner }
    )
  end

  # Public: Returns all the pinned repositories that the current user is authorized to see.
  # @return [Array<UserDashboardPin>]
  def authorized_pinned_items
    current_user.dashboard_pinned_items(
      viewer: current_user,
      types: ["Repository"],
      excluded_account_ids: unauthorized_account_ids,
      preload_scope: { pinned_item: :owner }
    )
  end

  # Public: Returns potential repositories the user is able to pin, based on their authorized access
  # @param items_per_page [Integer] The number of items to paginage by
  # @return [Array<UserDashboardPin>] returns pinnable repositories sorted by pinned items at the top, followed by other repositories
  def fetch_pinnable_items(items_per_page: 40)
    top = TopRepositories.for(viewer: current_user, since: 1.year.ago, cap_filter: cap_filter).to_a
    items = authorized_pinned_items + (top - authorized_pinned_items)

    GitHub::SimplePagination.paginate_collection(items, per_page: items_per_page, page: current_page)
  end

  # Public: Returns potential repositories the user is able to pin, based on their search query
  # @param query [String] The search query
  # @param items_per_page [Integer] The number of items to paginage by
  # @return [Array<Repository>] returns pinnable repositories sorted by pinned items at the top, followed by other repositories
  def fetch_pinnable_repositories(query, items_per_page: 40)
    helper = Search::QueryHelper.new("#{query} in:name", :repositories,
      current_user: current_user,
      remote_ip: request.remote_ip,
      page: current_page,
      per_page: items_per_page,
      user_session: user_session,
      request_id: request_id
    )
    data = helper.repo_query.execute
    repositories = data.results.map { |result| result.repo }

    collection = GitHub::SimplePagination::Collection.new(
      page: current_page,
      per_page: items_per_page,
      has_more: current_page < data.total_pages
    )

    collection.replace(repositories)
    collection
  end

  # Public: Returns the repositories that the user is not authorized
  # to see based on the CAP filter.
  # @return [Array<UserDashboardPin>] returns unauthorized pinned items
  def unauthorized_pinned_items
    all_pinned_items.select do |item|
      unauthorized_account_ids.include?(item.owner_id)
    end
  end

  # Public: Returns the ids of the Users/Organizations that the user is not authorized
  # to see based on the CAP filter.
  # @return [Array<Integer>]
  def unauthorized_account_ids
    cap_filter.unauthorized_resource_ids(current_user.resources_for_cap_filter)
  end

  def repo_aria_label(repo)
    return if repo.template?
    return "Forked repository" if repo.fork?
    "Repository"
  end

  def repo_visibility(repo)
    repo.private? ? "private" : "public"
  end

  def repo_attributes(repo: nil)
    repo_hash = {
      fork: repo.fork?,
      private: repo.private?,
      id: repo.global_relay_id
    }

    attrs = sidebar_repository_attributes(
      repo: repo_hash,
      event_context: Dashboard::EventContext::Sidebar::FAVORITES,
    )

    attrs.merge!(hovercard_data_attributes_for_repository(repo))
  end
end
