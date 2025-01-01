# typed: true
# frozen_string_literal: true

class Api::OrganizationImmutableReleasesSettings < Api::App
  include ReceiveSchemaWithOpenApi

  # Get the org policy for immutable releases
  get "/organizations/:organization_id/settings/immutable-releases", operation_id: "orgs/get-immutable-releases-settings" do
    current_org = find_org!
    config = Releases::ImmutableOrganizationConfig.new(current_org)

    ensure_feature_flag_enabled!(current_org)

    control_access :view_org_settings,
      resource: current_org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    enforced_repositories = config.immutable_releases_policy

    selected_repositories_url = nil
    if config.immutable_releases_enabled_for_selected?
      selected_repositories_url = url("/organizations/#{current_org.id}/settings/immutable-releases/repositories")
    end

    deliver :immutable_releases_organization_settings_hash, {
      enforced_repositories: enforced_repositories,
      selected_repositories_url: selected_repositories_url
    }
  end

  # Update the org policy for immutable releases
  put "/organizations/:organization_id/settings/immutable-releases", operation_id: "orgs/set-immutable-releases-settings", read_from_replicas: true do
    current_org = find_org!
    config = Releases::ImmutableOrganizationConfig.new(current_org)

    ensure_feature_flag_enabled!(current_org)

    control_access :update_org,
      resource: current_org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    data = receive_with_openapi
    enforced_repositories = data["enforced_repositories"]
    selected_repo_ids = data["selected_repository_ids"]

    # Verify list of selected repositories if provided
    if selected_repo_ids.present?
      if enforced_repositories != Releases::ImmutableOrganizationConfig::SELECTED
        deliver_error! 422, errors: "Selected repositories can only be set when the policy is set to 'selected'."
      end

      # Verify that the list matches repos within this organization
      all_repo_ids = current_org.repositories.pluck(:id)

      if (selected_repo_ids - all_repo_ids).any?
        deliver_error! 422, errors: "Some repositories in the selection do not belong to this organization."
      end

      # Update enforcement for selected repositories in background job
      ::Releases::Public.enforce_immutable_releases_in_selected_repos(current_org, selected_repo_ids, current_user)
    end

    with_write(clusters: [ApplicationRecord::Configurations]) do
      config.set_immutable_releases_policy(enforced_repositories, actor: current_user)
    end

    deliver_empty(status: 204)
  end

  # Get the list of enforced repositories for immutable releases
  get "/organizations/:organization_id/settings/immutable-releases/repositories", operation_id: "orgs/get-immutable-releases-settings-repositories" do
    current_org = find_org!

    ensure_feature_flag_enabled!(current_org)

    control_access :view_org_settings,
      resource: current_org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    # Return an error if the immutable releases policy is not set to SELECTED.
    config = Releases::ImmutableOrganizationConfig.new(current_org)
    check_policy_selected!(config)

    enforced_repo_ids = config.immutable_releases_enforced_repo_ids
    enforced_repos = current_org.repositories.order(:name).where(id: enforced_repo_ids)
    paginated_repo = paginate_rel(enforced_repos)

    deliver :immutable_releases_organization_enforced_repositories_hash, {
      total_count: enforced_repos.count,
      repositories: paginated_repo
    }
  end

  put "/organizations/:organization_id/settings/immutable-releases/repositories", operation_id: "orgs/set-immutable-releases-settings-repositories", read_from_replicas: true do
    current_org = find_org!

    ensure_feature_flag_enabled!(current_org)

    control_access :write_org_immutable_releases_settings,
      resource: current_org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    # Return an error if the immutable releases policy is not set to SELECTED.
    config = Releases::ImmutableOrganizationConfig.new(current_org)
    check_policy_selected!(config)

    data = receive_with_openapi
    selected_repo_ids = data["selected_repository_ids"]

    # Verify that the list matches repos within this organization
    all_repo_ids = current_org.repositories.pluck(:id)

    if (selected_repo_ids - all_repo_ids).any?
      deliver_error! 422, errors: "Some repositories in the selection do not belong to this organization."
    end

    # Update enforcement for selected repositories in background job
    ::Releases::Public.enforce_immutable_releases_in_selected_repos(current_org, selected_repo_ids, current_user)

    deliver_empty status: 204
  end

  # Enable repository for immutable releases enforcement
  put "/organizations/:organization_id/settings/immutable-releases/repositories/:repository_id", read_from_replicas: true, operation_id: "orgs/enable-selected-repository-immutable-releases-organization" do
    current_org = find_org!

    ensure_feature_flag_enabled!(current_org)

    control_access :write_org_immutable_releases_settings,
      resource: current_org,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true

    repo = find_and_check_repo!(current_org)

    # Return an error if the immutable releases policy is not set to SELECTED.
    config = Releases::ImmutableOrganizationConfig.new(current_org)
    check_policy_selected!(config)

    with_write(clusters: [ApplicationRecord::Configurations]) do
      config.enforce_immutable_releases_for_repo_ids([repo.id], actor: current_user)
    end

    deliver_empty(status: 204)
  end

  # Disable repository for immutable releases enforcement
  delete "/organizations/:organization_id/settings/immutable-releases/repositories/:repository_id", read_from_replicas: true, operation_id: "orgs/disable-selected-repository-immutable-releases-organization" do
    current_org = find_org!

    ensure_feature_flag_enabled!(current_org)

    control_access :write_org_immutable_releases_settings,
      resource: current_org,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true

    repo = find_and_check_repo!(current_org)

    # Return an error if the immutable releases policy is not set to SELECTED.
    config = Releases::ImmutableOrganizationConfig.new(current_org)
    check_policy_selected!(config)

    with_write(clusters: [ApplicationRecord::Configurations]) do
      config.unenforce_immutable_releases_for_repo_ids([repo.id], actor: current_user)
    end

    deliver_empty(status: 204)
  end

  private

  sig { params(config: Releases::ImmutableOrganizationConfig).void }
  def check_policy_selected!(config)
    case config.immutable_releases_policy
    when Releases::ImmutableOrganizationConfig::SELECTED
      # Policy is set to SELECTED, do nothing
    when Releases::ImmutableOrganizationConfig::ALL
      deliver_error! 409, message: "Immutable releases enforced for all repositories"
    when Releases::ImmutableOrganizationConfig::NONE
      deliver_error! 409, message: "Immutable releases not enforced for any repositories"
    end
  end

  sig { params(current_org: Organization).returns(Repository) }
  def find_and_check_repo!(current_org)
    repo = if FeatureFlag.vexi.enabled?(:repos_domain_find_by, default: false)
      T.cast(Repositories.domain.by_id(params[:repository_id].to_i), T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast
    else
      Repository.find_by(id: params[:repository_id].to_i)
    end

    deliver_error! 404 unless repo
    deliver_error! 422 unless repo.owner_id == current_org.id

    repo
  end

  sig { params(org: Organization).void }
  def ensure_feature_flag_enabled!(org)
    unless org.feature_flag_enabled?(:immutable_releases, default: false)
      deliver_error! 404
    end
  end
end
