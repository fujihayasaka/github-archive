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
    ApplicationRecord::Permissions,
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

    available_user_ids = available_assignee_ids_from_sources

    if include_bots?
      available_user_ids |= available_bot_ids_from_sources
    end

    scope = User.where(id: available_user_ids)

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
    # the current user (if logged in) when there is no query so that they are at least available in the initial result set
    user_ids = users.map(&:id)
    if logged_in?
      if !has_search_query? && user_ids.exclude?(current_user.id) && available_user_ids.include?(current_user.id)
        users << current_user
      end
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
    return nil unless query_value.present? && (has_repository_context? || logged_in?)

    if query_value.start_with?("app/")
      Bot.find_by_slug(query_value.delete_prefix("app/"))
    else
      User.find_by_login(query_value).tap { |user| return nil if user&.hide_from_user?(current_user) || user.is_a?(Organization) }
    end
  end

  # Return the user IDs relevant to the user's repository context / top repos
  # If logged out and there's no repo context, return nothing
  memoize def available_assignee_ids_from_sources
    return [] unless has_repository_context? || logged_in?

    repos = has_repository_context? ? repositories_from_query : find_top_repositories
    repos.flat_map { |repo| repo.available_assignee_ids(limit: AVAILABLE_USERS_LIMIT) }.uniq
  end

  # Return the bot accounts user IDs for the installed apps of the repository,
  # if the repository is present in the query
  memoize def available_bot_ids_from_sources
    return [] unless has_repository_context?

    repos = repositories_from_query
    installations = repos.map { |repo| IntegrationInstallation.with_repository(repo).includes(integration: :bot) }.flatten
    return [] unless installations.length > 0

    integrations = installations.map(&:integration).uniq
    return [] unless integrations.length > 0

    bots = integrations.map(&:bot)
    bots.compact!
    bots.map(&:id).uniq
  end

  # include_bots param is a boolean that will be considered true if part of the query params,
  # regardless of its value
  memoize def include_bots?
    params.has_key?(:include_bots)
  end

  def format_response(user)
    {
      name: user.safe_profile_name,
      login: user.is_a?(Bot) ? user.to_query_filter : user.display_login,
      avatarUrl: user.primary_avatar_url(60),
    }
  end

  def target_for_conditional_access
    user_from_query || current_user || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
