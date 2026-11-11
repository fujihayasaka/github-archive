# typed: true
# frozen_string_literal: true

class Api::InteractionLimits < Api::App
  include ReceiveSchemaWithOpenApi
  include Scientist

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
  put "/repositories/:repository_id/interaction-limits", operation_id: "interactions/set-restrictions-for-repo" do
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

    result = InteractionLimits::SetInteractionLimit.call(inputs)

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
  put "/user/interaction-limits", operation_id: "interactions/set-restrictions-for-authenticated-user" do
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

    result = InteractionLimits::SetInteractionLimit.call(inputs)

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
