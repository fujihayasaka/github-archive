# typed: true
# frozen_string_literal: true

class Api::UserBlocking < Api::App
  include ReceiveSchemaWithOpenApi

  # List users the authenticated user is blocking
  get "/user/blocks", operation_id: "users/list-blocked-by-authenticated-user" do
    control_access :read_blocks,
      resource: current_user,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    users = paginate_rel(current_user.ignored.not_spammy)
    deliver :user_hash, users
  end

  # Get if the authenticated User is blocking a User
  get "/user/blocks/:username", operation_id: "users/check-blocked" do
    control_access :read_blocks,
      resource: current_user,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    other_user = this_user

    if !other_user.spammy? && current_user.blocking?(other_user)
      deliver_empty(status: 204)
    else
      deliver_error 404
    end
  end

  # Block a User
  put "/user/blocks/:username", operation_id: "users/block" do
    # Introducing strict validation of the user.block
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    receive_with_schema("user", "block", skip_validation: true)

    control_access :block,
      resource: current_user,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    can_block = current_user.can_block(this_user)
    if can_block.blockable?
      current_user.block(this_user)
      deliver_empty(status: 204)
    else
      deliver_error!(422, message: can_block.reason)
    end
  end

  # Unblock a User
  delete "/user/blocks/:username", operation_id: "users/unblock" do
    receive_with_schema("user", "unblock")

    control_access :unblock,
      resource: current_user,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    current_user.unblock(this_user)

    deliver_empty(status: 204)
  end

  # List users the org is blocking
  get "/organizations/:organization_id/blocks", operation_id: "orgs/list-blocked-users" do
    org = find_org!
    control_access :read_org_blocks,
      resource: org,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    users = paginate_rel(org.ignored.not_spammy)
    deliver :user_hash, users
  end

  # Get if the authenticated User is blocking a User
  get "/organizations/:organization_id/blocks/:username", operation_id: "orgs/check-blocked-user" do
    org = find_org!
    control_access :read_org_blocks,
      resource: org,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    other_user = this_user

    if !other_user.spammy? && org.blocking?(other_user)
      deliver_empty(status: 204)
    else
      deliver_error 404
    end
  end

  # Block a User
  put "/organizations/:organization_id/blocks/:username", operation_id: "orgs/block-user" do
    # Introducing strict validation of the user.block-from-organization
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    receive_with_schema("user", "block-from-organization", skip_validation: true)

    org = find_org!
    control_access :manage_org_blocks,
      resource: org,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    can_block = org.can_block(this_user)
    if can_block.blockable?
      org.block(this_user)
      deliver_empty(status: 204)
    else
      deliver_error!(422, message: can_block.reason)
    end
  end

  # Unblock a User
  delete "/organizations/:organization_id/blocks/:username", operation_id: "orgs/unblock-user" do
    receive_with_schema("user", "unblock-in-org")

    org = find_org!
    control_access :manage_org_blocks,
      resource: org,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    org.unblock(this_user)

    deliver_empty(status: 204)
  end
end
