# typed: true
# frozen_string_literal: true

class FilterProviders::UsersController < FilterProvidersController
  include FilterProviders::RepositoriesDependency

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    only: [:index, :show]

  depends_on_clusters ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Repositories,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Iam,
    only: [:index]

  # We want a high enough limit for most orgs/repos, but low enough to prevent timeouts for extremely large orgs
  AVAILABLE_USERS_LIMIT = 10_000

  def index
    respond_payload({
      users: fetch_users.map { |user| format_response(user) }
    })
  end

  def show
    if user_from_query.present?
      respond_payload(format_response(user_from_query))
    else
      head :unprocessable_entity
    end
  end

  private

  def fetch_users
    return [] if available_assignee_ids_from_sources.empty?

    scope = User.where(id: available_assignee_ids_from_sources)

    users = if has_search_query?
      scope = scope.like_login_or_profile_name(query_value)
        .filter_spam_for(current_user)
        .limit(maximum_result_limit)
        .to_a
    else
      scope.order("users.login")
        .filter_spam_for(current_user)
        .limit(maximum_result_limit)
        .includes(:profile)
        .to_a
    end

    users = users.take(maximum_result_limit)

    # users searching for things associated with themselves is a common use case, so we always include
    # the current user when there is no query so that they are at least available in the initial result set
    user_ids = users.map(&:id)
    if !has_search_query? && user_ids.exclude?(current_user.id) && available_assignee_ids_from_sources.include?(current_user.id)
      users << current_user
    end

    if has_search_query?
      users.sort_by do |u|
        [
          u.display_login.start_with?(query_value) ? "0" : "1",
          u.safe_profile_name.start_with?(query_value) ? "0" : "1",
          u.display_login
        ]
      end
    else
      users.sort_by(&:display_login)
    end
  end

  memoize def user_from_query
    return nil unless query_value.present?
    if query_value.start_with?("app/")
      Bot.find_by_slug(query_value.delete_prefix("app/"))
    else
      User.find_by_login(query_value).tap { |user| return nil if user&.hide_from_user?(current_user) }
    end
  end

  # Return the user IDs relevant to the user's repository context / top repos
  memoize def available_assignee_ids_from_sources
    repos = has_repository_context? ? repositories_from_query : find_top_repositories
    repos.flat_map { |repo| repo.available_assignee_ids(limit: AVAILABLE_USERS_LIMIT) }.uniq
  end

  def format_response(user)
    {
      name: user.safe_profile_name,
      login: user.display_login,
      avatarUrl: user.primary_avatar_url(60),
    }
  end

  def target_for_conditional_access
    # login is required on this controller, but this method runs before the login_required filter
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    user_from_query || current_user
  end
end
