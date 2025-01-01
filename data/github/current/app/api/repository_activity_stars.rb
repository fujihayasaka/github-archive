# typed: true
# frozen_string_literal: true

class Api::RepositoryActivityStars < Api::App
  register Api::App::MultiRoute
  include ::Api::App::ProtectedResourcesFilter
  include FeatureFlagHelper
  include ReceiveSchemaWithOpenApi

  # List repositories the authenticated user has starred
  get "/user/starred", operation_id: "activity/list-repos-starred-by-authenticated-user" do
    require_authentication!
    control_access :list_starred,
      resource: Platform::PublicResource.new, # rubocop:disable GitHub/PublicResource
      allow_integrations: false,
      allow_user_via_granular_actor: true

    current_user_stars = stars_for current_user

    if unauthorized_account_ids.any?
      set_sso_partial_results_header(unauthorized_sso_org_ids) if unauthorized_sso_org_ids.any?
      current_user_stars = filter_protected_resources \
        type: :starred,
        resources: current_user_stars,
        protected_account_ids: unauthorized_account_ids
    end

    prefill_stars(current_user_stars)

    if medias.api_param?(:star)
      deliver :star_hash_with_timestamps, current_user_stars
    else
      deliver :star_hash, current_user_stars
    end
  end

  get "/user/watched", operation_id: :deprecated do
    require_authentication!
    control_access :list_starred,
      resource: Platform::PublicResource.new(resource: current_user),
      allow_integrations: false,
      allow_user_via_granular_actor: true

    stars = stars_for current_user
    prefill_stars(stars)

    if medias.api_param?(:star)
      deliver :star_hash_with_timestamps, stars
    else
      deliver :star_hash, stars
    end
  end

  # List repositories a user has starred
  get "/user/:user_id/starred", operation_id: "activity/list-repos-starred-by-user" do
    user = find_user!

    control_access :list_starred,
      resource: Platform::PublicResource.new(resource: user),
      user: user, # rubocop:disable GitHub/DisallowEgressUserKey
      allow_integrations: true,
      allow_user_via_granular_actor: true

    stars = stars_for user
    prefill_stars(stars)

    if medias.api_param?(:star)
      deliver :star_hash_with_timestamps, stars
    else
      deliver :star_hash, stars
    end
  end

  get "/user/:user_id/watched", operation_id: :deprecated do
    user = find_user!

    control_access :list_starred,
      resource: Platform::PublicResource.new(resource: user),
      user: user, # rubocop:disable GitHub/DisallowEgressUserKey
      allow_integrations: true,
      allow_user_via_granular_actor: true

    stars = stars_for user
    prefill_stars(stars)

    if medias.api_param?(:star)
      deliver :star_hash_with_timestamps, stars
    else
      deliver :star_hash, stars
    end
  end

  # Get if a repository is starred by the authenticated user
  get "/user/starred/:owner/:repo", operation_id: "activity/check-repo-is-starred-by-authenticated-user" do
    require_authentication!

    repo = this_repo
    @accepted_scopes = repo.public? ? %w(public_repo repo) : %w(repo)

    control_access :get_star,
      resource: repo,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    if Stars.domain.repo_starred_by_user?(repo.id, current_user.id)
      deliver_empty(status: 204)
    else
      deliver_error 404
    end
  end

  get "/user/watched/:owner/:repo", operation_id: :deprecated do
    require_authentication!

    repo = this_repo
    @accepted_scopes = repo.public? ? %w(public_repo repo) : %w(repo)

    control_access :get_star,
      resource: repo,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    if Stars.domain.repo_starred_by_user?(repo.id, current_user.id)
      deliver_empty(status: 204)
    else
      deliver_error 404
    end
  end

  # Star a repository
  put "/user/starred/:owner/:repo", operation_id: "activity/star-repo-for-authenticated-user" do
    # Introducing strict validation of the repository.star
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    receive_with_schema("repository", "star", skip_validation: true)

    require_authentication!

    repo = this_repo
    @accepted_scopes = repo.public? ? %w(public_repo repo) : %w(repo)

    control_access :star,
      resource: repo,
      enforce_oauth_app_policy: repo.private?,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    star_result = Stars.domain.star_repository(user: current_user, repository: repo, context: "api")
    if star_result.is_a?(GH::Result::Error::ContentAuthorizationError)
      deliver_content_authorization_denied!(star_result.authorization)
    end

    deliver_empty(status: 204)
  end

  put "/user/watched/:owner/:repo", operation_id: :deprecated do
    require_authentication!

    repo = this_repo
    @accepted_scopes = repo.public? ? %w(public_repo repo) : %w(repo)

    control_access :star,
      resource: repo,
      enforce_oauth_app_policy: repo.private?,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    Stars.domain.star_repository(user: current_user, repository: repo, context: "api")

    deliver_empty(status: 204)
  end

  # Unstar a repository
  delete "/user/starred/:owner/:repo", operation_id: "activity/unstar-repo-for-authenticated-user" do
    # Introducing strict validation of the repository.unstar
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    receive_with_schema("repository", "unstar", skip_validation: true)

    require_authentication!

    repo = this_repo
    @accepted_scopes = repo.public? ? %w(public_repo repo) : %w(repo)

    control_access :unstar,
      resource: repo,
      enforce_oauth_app_policy: repo.private?,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    current_user.unstar repo

    deliver_empty(status: 204)
  end

  delete "/user/watched/:owner/:repo", operation_id: :deprecated do
    require_authentication!

    repo = this_repo
    @accepted_scopes = repo.public? ? %w(public_repo repo) : %w(repo)

    control_access :unstar,
      resource: repo,
      enforce_oauth_app_policy: repo.private?,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    current_user.unstar repo

    deliver_empty(status: 204)
  end

  # List users starring a repository
  get "/repositories/:repository_id/stargazers", operation_id: "activity/list-stargazers-for-repo" do
    control_access :list_stargazers,
      resource: repo = find_repo!,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    cap_paginated_entries!

    if repo.owner.feature_enabled?(:limit_user_repo_stars_query)
      deliver :stargazer_hash, []
    end

    requested_pagination = GH::Pagination::Offset.new(
      page: pagination[:page],
      per_page: pagination[:per_page]
    )

    stargazers = Stars.domain.repo_stars_not_spammy_for_viewer(repo.id, viewer: current_user, pagination: requested_pagination)

    GitHub::PrefillAssociations.prefill_associations(stargazers, :user)

    if medias.api_param?(:star)
      deliver :stargazer_hash_with_timestamps, stargazers
    else
      deliver :stargazer_hash, stargazers
    end
  end

  get "/repositories/:repository_id/watchers", operation_id: :deprecated do
    control_access :list_stargazers, resource: repo = find_repo!,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    cap_paginated_entries!

    requested_pagination = GH::Pagination::Offset.new(
      page: pagination[:page],
      per_page: pagination[:per_page]
    )

    stargazers = Stars.domain.repo_stars_not_spammy_for_viewer(repo.id, viewer: current_user, pagination: requested_pagination)

    GitHub::PrefillAssociations.prefill_associations(stargazers, :user)

    if medias.api_param?(:star)
      deliver :stargazer_hash_with_timestamps, stargazers
    else
      deliver :stargazer_hash, stargazers
    end
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

  def stars_for(user)
    if user.private_profile_for?(current_user)
      return paginate_rel(Star.none)
    end

    access_allowed = access_allowed?(:list_private_stars, resource: user, allow_integrations: false, allow_user_via_granular_actor: true)
    order = params[:sort]
    direction = params[:direction]
    direction = (direction == "asc" ? :asc : :desc)

    starrable_ids = if GitHub.flipper[:stars_domain_api_repository_activity].enabled?
      user.starred_repository_ids(limit: Star::STARRED_REPOSITORY_LIMIT)
    else
      user.stars.repositories.limit(Star::STARRED_REPOSITORY_LIMIT).pluck(:starrable_id)
    end

    starred_repo_scope = if access_allowed
      Platform::Security::RepositoryAccess.with_viewer(current_user) do
        permission = Platform::Authorization::Permission.new(viewer: current_user, integration: current_integration, origin: Platform::ORIGIN_API)
        permission.filtered_permissible_repository_scope(user, starrable_ids, resource: "metadata")
      end
    else
      Repositories::Public.where_public(starrable_ids)
    end

    case order
    when "updated"
      ordered_scope = starred_repo_scope.order(pushed_at: direction).order(:id)
      paginate_stars(user, ordered_scope)
    when  "stars"
      ordered_scope = starred_repo_scope.order("#{Repository.stargazer_count_column} #{direction}").order(:id)
      paginate_stars(user, ordered_scope)
    else
      starred_repository_ids = starred_repo_scope.ids
      scope = user.stars.repositories.where(starrable_id: starred_repository_ids).order(created_at: direction)
      scope = scope.force_index(:user_id_and_starrable_type_and_created_at_and_starrable_id)
      paginate_rel(scope)
    end
  end

  def authorize_content(kind, operation = :create, data = {})
    authorization = ContentAuthorizer.authorize(current_user, kind, operation, data)
    if authorization.failed?
      deliver_error! authorization.http_error_code, authorization.api_error_payload
    end
  end

  def paginate_stars(user, ordered_scope)
    paginated_scope = ordered_scope.paginate(per_page: pagination[:per_page], page: pagination[:page])
    ids_for_page = paginated_scope.ids

    WillPaginate::Collection.create(pagination[:page], pagination[:per_page], paginated_scope.total_entries) do |page|
      page.replace(user.stars.repositories.where("stars.starrable_id": ids_for_page).order(
          Arel.sql("FIELD(starrable_id, #{ids_for_page.join(",")})"), "id"
      ))
    end
  end

  def prefill_stars(stars)
    repo_stars = stars.select { |s| s.starrable_type == Star::STARRABLE_TYPE_REPOSITORY }
    GitHub::PrefillAssociations.prefill_associations(repo_stars, :starrable)
    Repository.prefill_associations(stars.map(&:starrable).compact)
  end
end
