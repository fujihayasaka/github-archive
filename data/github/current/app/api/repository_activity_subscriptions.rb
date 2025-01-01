# typed: true
# frozen_string_literal: true

class Api::RepositoryActivitySubscriptions < Api::App
  register Api::App::MultiRoute
  include ::Api::App::ProtectedResourcesFilter
  include ReceiveSchemaWithOpenApi

  # List repositories the authenticated user is watching
  get "/user/subscriptions", operation_id: "activity/list-watched-repos-for-authenticated-user" do
    require_authentication!
    control_access :list_watched,
      resource: Platform::PublicResource.new, # rubocop:disable GitHub/PublicResource
      allow_integrations: false,
      allow_user_via_granular_actor: true

    repos = watched_repos_for current_user

    if unauthorized_account_ids.any?
      set_sso_partial_results_header(unauthorized_sso_org_ids) if unauthorized_sso_org_ids.any?
      repos = filter_protected_resources \
        type: :watched,
        resources: repos,
        protected_account_ids: unauthorized_account_ids
    end

    Repository.prefill_associations(repos)

    deliver :repository_hash, repos
  end

  # List repositories a user is watching
  get "/user/:user_id/subscriptions", operation_id: "activity/list-repos-watched-by-user" do
    user = find_user!

    control_access :list_watched,
      resource: Platform::PublicResource.new(resource: user),
      user: user,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    repos = watched_repos_for user

    Repository.prefill_associations(repos)

    deliver :repository_hash, repos
  end

  # Get if a repository is watched by the authenticated user
  get "/user/subscriptions/:owner/:repo", operation_id: :deprecated do
    require_authentication!
    repo = this_repo

    @accepted_scopes = repo.public? ? %w(public_repo repo) : %w(repo)

    control_access :read_user_repo_subscription,
      resource: repo,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    status_response = GitHub.newsies.subscription_status(current_user, repo)
    if status_response.failed?
      deliver_notifications_unavailable!
    end

    if status_response.subscribed?
      deliver_empty(status: 204)
    else
      deliver_error 404
    end
  end

  # Watch a repository
  put "/user/subscriptions/:owner/:repo", operation_id: :deprecated do
    require_authentication!
    repo = this_repo

    @accepted_scopes = repo.public? ? %w(public_repo repo) : %w(repo)

    control_access :write_user_repo_subscription,
      resource: repo,
      enforce_oauth_app_policy: repo.private?,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    current_user.watch_repo repo

    deliver_empty(status: 204)
  end

  # Unwatch a repository
  delete "/user/subscriptions/:owner/:repo", operation_id: :deprecated do
    require_authentication!
    repo = this_repo

    @accepted_scopes = repo.public? ? %w(public_repo repo) : %w(repo)

    control_access :write_user_repo_subscription,
      resource: repo,
      enforce_oauth_app_policy: repo.private?,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    current_user.unwatch_repo repo

    deliver_empty(status: 204)
  end

  # List users watching a repository
  get "/repositories/:repository_id/subscribers", operation_id: "activity/list-watchers-for-repo" do
    control_access :list_watchers, resource: repo = find_repo!,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    watchers_response = repo.watchers(pagination[:page], pagination[:per_page])
    if watchers_response.failed?
      deliver_notifications_unavailable!
    end
    watchers = watchers_response.value

    deliver :user_hash, watchers
  end

  private

  def unauthorized_account_ids
    return @unauthorized_account_ids if defined?(@unauthorized_account_ids)
    @unauthorized_account_ids = cap_filter.unauthorized_resource_ids(
      current_user&.resources_for_cap_filter
    )
  end

  def unauthorized_sso_org_ids
    return @unauthorized_sso_org_ids if defined?(@unauthorized_sso_org_ids)
    @unauthorized_sso_org_ids = cap_filter.unauthorized_resource_ids(
      current_user&.organizations,
      only: :saml
    )
  end

  def watched_repos_for(user)
    if GitHub.flipper[:notifications_exclude_watcher_users].enabled?(user)
      GitHub.logger.info("excluded user from querying watcher subscriptions", {
        "code.namespace" => self.class.name,
        "code.function" => "watched_repos_for",
        "gh.user.id" => user.id
      })

      deliver_notifications_unavailable!
    end

    watched_repositories = WatchedRepositories.new(user)

    response = if access_allowed?(:list_private_watched_repos, resource: user, allow_integrations: false, allow_user_via_granular_actor: true)
      if ProgrammaticActor::RepositoryFilter.applicable?(current_user)
        watched_repositories.user_via_granular_actor_paginate(current_user, pagination)
      elsif requestor_governed_by_oauth_application_policy?
        watched_repositories.oap_paginate(current_app, pagination)
      else
        watched_repositories.paginate(pagination)
      end
    else
      watched_repositories.public_paginate(pagination)
    end

    if response.failed?
      deliver_notifications_unavailable!
    end

    response.value
  end
end
