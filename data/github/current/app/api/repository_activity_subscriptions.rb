# typed: true
# frozen_string_literal: true

class Api::RepositoryActivitySubscriptions < Api::App
  register Api::App::MultiRoute
  include ::Api::App::ProtectedResourcesFilter
  include ReceiveSchemaWithOpenApi

  # List repositories the authenticated user is watching
  get "/user/subscriptions", operation_id: "activity/list-watched-repos-for-authenticated-user" do
    require_authentication!
    control_access :list_user_watched,
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
      allow_integrations: true,
      allow_user_via_granular_actor: true

    if FeatureFlag.vexi.enabled?(:public_api_repository_activity_tracking, current_user, default: false)
      GlobalInstrumenter.instrument("notifications.telemetry", {
        user: current_user,
        event: "public_api_request",
        metadata: {
          action: "repository_user_subscriptions",
          target_user_id: user.id
        },
      })
    end

    repos = watched_repos_for user

    if unauthorized_account_ids.any?
      set_sso_partial_results_header(unauthorized_sso_org_ids) if unauthorized_sso_org_ids.any?
      repos = filter_protected_resources \
        type: :watched,
        resources: repos,
        protected_account_ids: unauthorized_account_ids
    end

    Repository.prefill_associations(repos)

    if FeatureFlag.vexi.enabled?(:restrict_access_stargazers_endpoints, current_user, default: false)
      # This is a temporary change until this endpoint is permanently deleted.
      # Context: https://github.com/github/fixing-oss-pain-points/issues/252
      deliver_empty(status: 204)
    else
      deliver :repository_hash, repos
    end
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

    subscribed = Notifications::Subscriptions.repository_subscribed?(current_user, repo)
    if subscribed.nil?
      deliver_notifications_unavailable!
    end

    if subscribed
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
    if FeatureFlag.vexi.enabled?(:restrict_access_stargazers_endpoints, current_user, default: false)
      control_access :list_collaborators, resource: repo = find_repo!,
        challenge: repo.public?,
        allow_integrations: true,
        allow_user_via_granular_actor: true
    else
      control_access :list_watchers, resource: repo = find_repo!,
        allow_integrations: true,
        allow_user_via_granular_actor: true
    end

    if FeatureFlag.vexi.enabled?(:public_api_repository_activity_tracking, current_user, default: false)
      GlobalInstrumenter.instrument("notifications.telemetry", {
        user: current_user,
        event: "public_api_request",
        metadata: {
          action: "repository_subscribers_list",
        },
      })
    end

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
    @unauthorized_account_ids = if current_user
      current_user.unauthorized_resource_ids(cap_filter)
    else
      []
    end
  end

  def unauthorized_sso_org_ids
    return @unauthorized_sso_org_ids if defined?(@unauthorized_sso_org_ids)
    @unauthorized_sso_org_ids = cap_filter.unauthorized_resource_ids(
      current_user&.organizations,
      only: :saml
    )
  end

  def watched_repos_for(user)
    if FeatureFlag.vexi.enabled?(:notifications_exclude_watcher_users, user, default: false)
      GitHub.logger.info("excluded user from querying watcher subscriptions", {
        "code.namespace" => self.class.name,
        "code.function" => "watched_repos_for",
        "gh.user.id" => user.id
      })

      deliver_notifications_unavailable!
    end

    watched_repositories = WatchedRepositories.new(user)

    allow_private = access_allowed?(:list_private_watched_repos, resource: user, allow_integrations: false, allow_user_via_granular_actor: true)

    response = if allow_private
      if FeatureFlag.vexi.enabled?(:api_watched_restrict_finegrained_pat_repos, current_user, default: false) &&
        current_user&.using_auth_via_user_programmatic_access?
        watched_repositories.user_via_granular_actor_paginate(
          current_user,
          pagination,
          include_fine_grained_pat_restrictions: true,
        )
      elsif ProgrammaticActor::RepositoryFilter.applicable?(current_user)
        watched_repositories.user_via_granular_actor_paginate(current_user, pagination)
      elsif requestor_governed_by_oauth_application_policy?
        watched_repositories.oap_paginate(current_app, pagination)
      elsif FeatureFlag.vexi.enabled?(:api_watched_restrict_pat_repos, current_user, default: false) &&
        current_user&.using_personal_access_token?
        watched_repositories.classic_pat_paginate(pagination)
      else
        watched_repositories.paginate(pagination)
      end
    else
      if FeatureFlag.vexi.enabled?(:api_watched_restrict_finegrained_pat_repos, current_user, default: false) &&
        current_user&.using_auth_via_user_programmatic_access?
        watched_repositories.public_user_via_granular_actor_paginate(
          current_user,
          pagination,
          include_fine_grained_pat_restrictions: true,
        )
      elsif ProgrammaticActor::RepositoryFilter.applicable?(current_user)
        watched_repositories.public_user_via_granular_actor_paginate(current_user, pagination)
      elsif FeatureFlag.vexi.enabled?(:api_watched_restrict_pat_repos, current_user, default: false) &&
        current_user&.using_personal_access_token?
        watched_repositories.public_classic_pat_paginate(pagination)
      else
        watched_repositories.public_paginate(pagination)
      end
    end

    if response.failed?
      deliver_notifications_unavailable!
    end

    response.value
  end
end
