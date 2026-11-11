# typed: true
# frozen_string_literal: true

class Api::InteractionLimits < Api::App
  include ReceiveSchemaWithOpenApi
  include Scientist

  SIZE_LIMIT = 100

  before do
    deliver_error!(404) unless GitHub.interaction_limits_enabled?
  end

  # Access the interaction ability settings for a repository
  get "/repositories/:repository_id/interaction-limits", operation_id: "interactions/get-restrictions-for-repo" do
    repo = find_repo!

    control_access :read_repository_interaction_limits,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: repo.public?

    if repo.private?
      deliver_error! 405, errors: "Interaction limits cannot be set for private repositories."
    end

    deliver :interaction_ability_hash, repo
  end

  # Set the interaction ability settings for a repository
  put "/repositories/:repository_id/interaction-limits", operation_id: "interactions/set-restrictions-for-repo", read_from_replicas: true do
    repo = find_repo!

    control_access :set_repository_interaction_limits,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: repo.public?

    if repo.private?
      deliver_error! 405, errors: "Interaction limits cannot be set for private repositories."
    end

    if RepositoryInteractionAbility.has_active_limits?(repo.owner)
      owner_phrase = repo.owner.organization? ? "an organization" : "a user"
      deliver_error! 409, errors: "You cannot set repository level interaction limits when #{owner_phrase} level limit is enabled."
    end

    data = receive_with_schema("interaction-limit", "update-for-repository")

    inputs = {
      object: repo,
      limit: limit_name(data["limit"]),
      duration: limit_expiry(data["expiry"]),
      actor: current_user,
    }

    result = with_write(clusters: [ApplicationRecord::Collab]) do
      InteractionLimits::SetInteractionLimit.call(inputs)
    end

    if result.success?
      deliver :interaction_ability_hash, repo
    else
      deliver_error! 422,
        errors: result.error,
        documentation_url: @documentation_url
    end
  end

  # Disable any active interaction limit for a repository
  delete "/repositories/:repository_id/interaction-limits", operation_id: "interactions/remove-restrictions-for-repo" do
    repo = find_repo!

    control_access :set_repository_interaction_limits,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: repo.public?

    receive_with_schema("interaction-limit", "delete-for-repository")

    if repo.private?
      deliver_error! 405, errors: "Interaction limits cannot be set for private repositories."
    end

    if RepositoryInteractionAbility.has_active_limits?(repo.owner)
      owner_phrase = repo.owner.organization? ? "an organization" : "a user"
      deliver_error! 409, errors: "You cannot set repository level interaction limits when #{owner_phrase} level limit is enabled."
    end

    inputs = {
      object: repo,
      limit: :no_limit,
      actor: current_user,
    }

    result = InteractionLimits::SetInteractionLimit.call(inputs)

    if result.success?
      deliver_empty status: 204
    else
      deliver_error! 422,
        errors: result.error,
        documentation_url: @documentation_url
    end
  end

  # Access the interaction ability settings for an organization
  get "/organizations/:organization_id/interaction-limits", operation_id: "interactions/get-restrictions-for-org" do
    org = find_org!

    control_access :read_organization_interaction_limits,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true

    deliver :interaction_ability_hash, org
  end

  # Set the interaction ability settings for an organization
  put "/organizations/:organization_id/interaction-limits", operation_id: "interactions/set-restrictions-for-org" do
    org = find_org!

    control_access :set_organization_interaction_limits,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true

    data = receive_with_schema("interaction-limit", "update-for-organization")

    inputs = {
      object: org,
      limit: limit_name(data["limit"]),
      duration: limit_expiry(data["expiry"]),
      actor: current_user,
    }

    result = InteractionLimits::SetInteractionLimit.call(inputs)

    if result.success?
      deliver :interaction_ability_hash, org
    else
      deliver_error! 422,
        errors: result.error,
        documentation_url: @documentation_url
    end
  end

  # Disable any active interaction limit for an organization
  delete "/organizations/:organization_id/interaction-limits", operation_id: "interactions/remove-restrictions-for-org" do
    org = find_org!

    control_access :set_organization_interaction_limits,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true

    receive_with_schema("interaction-limit", "delete-for-organization")

    inputs = {
      object: org,
      limit: :no_limit,
      actor: current_user,
    }

    result = InteractionLimits::SetInteractionLimit.call(inputs)

    if result.success?
      deliver_empty status: 204
    else
      deliver_error! 422,
        errors: result.error,
        documentation_url: @documentation_url
    end
  end

  # Access the interaction ability settings for a user
  get "/user/interaction-limits", operation_id: "interactions/get-restrictions-for-authenticated-user" do
    control_access :read_user_interaction_limits,
                   resource: current_user,
                   forbid: true,
                   challenge: true,
                   allow_integrations: false,
                   allow_user_via_granular_actor: true

    deliver :interaction_ability_hash, current_user
  end

  # Set the interaction ability settings for a user
  put "/user/interaction-limits", operation_id: "interactions/set-restrictions-for-authenticated-user", read_from_replicas: true do
    control_access :write_user_interaction_limits,
      resource: current_user,
      forbid: true,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    data = receive_with_schema("interaction-limit", "update-for-user")

    inputs = {
      object: current_user,
      limit: limit_name(data["limit"]),
      duration: limit_expiry(data["expiry"]),
      actor: current_user,
    }

    result = with_write(clusters: [ApplicationRecord::Collab]) do
      InteractionLimits::SetInteractionLimit.call(inputs)
    end

    if result.success?
      deliver :interaction_ability_hash, current_user
    else
      deliver_error! 422,
        errors: result.error,
        documentation_url: @documentation_url
    end
  end

  # Disable any active interaction limit for a user
  delete "/user/interaction-limits", operation_id: "interactions/remove-restrictions-for-authenticated-user" do
    control_access :write_user_interaction_limits,
      resource: current_user,
      forbid: true,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    receive_with_schema("interaction-limit", "delete-for-user")

    inputs = {
      object: current_user,
      limit: :no_limit,
      actor: current_user,
    }

    result = InteractionLimits::SetInteractionLimit.call(inputs)

    if result.success?
      deliver_empty status: 204
    else
      deliver_error! 422,
        errors: result.error,
        documentation_url: @documentation_url
    end
  end

  # List the users on the pull request creation cap bypass list for a repository
  get "/repositories/:repository_id/interaction-limits/pulls/bypass-list", operation_id: "interactions/get-pull-request-bypass-list-for-repo" do
    repo = find_repo!

    deliver_error!(404) unless FeatureFlag.vexi.enabled?(:pull_request_creation_cap_allowlist_via_api, repo, default: false)

    control_access :read_repository_interaction_limits,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: repo.public?

    config = PullRequestCreationConfig.new(repo)
    user_ids = config.pull_request_creation_cap_bypass_user_ids

    users = user_ids.any? ? User.where(id: user_ids).to_a : []
    deliver :simple_user_hash, users
  end

  # Add users to the pull request creation cap bypass list for a repository
  put "/repositories/:repository_id/interaction-limits/pulls/bypass-list", operation_id: "interactions/set-pull-request-bypass-list-for-repo", read_from_replicas: true do
    repo = find_repo!

    deliver_error!(404) unless FeatureFlag.vexi.enabled?(:pull_request_creation_cap_allowlist_via_api, repo, default: false)

    control_access :set_repository_interaction_limits,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: repo.public?

    data = receive_with_openapi

    logins = data["users"] || []
    deliver_error!(422, message: "You can add a maximum of #{SIZE_LIMIT} users per request.") if logins.size > SIZE_LIMIT

    users = User.where(login: logins).to_a
    deliver_error!(422, message: "Could not find all specified users.") if users.size != logins.size

    with_write(clusters: [ApplicationRecord::IssuesPullRequests]) do
      config = PullRequestCreationConfig.new(repo)
      current_count = config.pull_request_creation_cap_bypass_user_ids.size
      max = Configurable::PullRequestCreationCapBypass::BYPASS_USER_IDS_MAX
      remaining = max - current_count

      if users.size > remaining
        deliver_error!(422, message: "The bypass list can hold a maximum of #{max} users. " \
          "There are currently #{current_count} users on the list; you can add up to #{remaining} more.")
      end

      begin
        config.add_pull_request_creation_cap_bypass_users(users: users)
      rescue ArgumentError => e
        deliver_error!(422, message: e.message)
      end
    end

    deliver_empty(status: 204)
  end

  # Remove users from the pull request creation cap bypass list for a repository
  delete "/repositories/:repository_id/interaction-limits/pulls/bypass-list", operation_id: "interactions/remove-pull-request-bypass-list-for-repo", read_from_replicas: true do
    repo = find_repo!

    deliver_error!(404) unless FeatureFlag.vexi.enabled?(:pull_request_creation_cap_allowlist_via_api, repo, default: false)

    control_access :set_repository_interaction_limits,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: repo.public?

    data = receive_with_openapi

    logins = data["users"] || []
    deliver_error!(422, message: "You can remove a maximum of #{SIZE_LIMIT} users per request.") if logins.size > SIZE_LIMIT

    users = User.where(login: logins).to_a
    deliver_error!(422, message: "Could not find all specified users.") if users.size != logins.size

    with_write(clusters: [ApplicationRecord::IssuesPullRequests]) do
      config = PullRequestCreationConfig.new(repo)
      config.remove_pull_request_creation_cap_bypass_users(users: users)
    end

    deliver_empty(status: 204)
  end

  private

  def limit_name(limit)
    # `sockpuppet_disallowed` is our internal name, but users know it as
    # `existing_users`, so we have to special case this.
    if limit == "existing_users"
      :sockpuppet_disallowed
    else
      limit.to_sym
    end
  end

  def limit_expiry(expiry)
    if expiry.present?
      expiry.to_sym
    else
      :one_day
    end
  end
end
