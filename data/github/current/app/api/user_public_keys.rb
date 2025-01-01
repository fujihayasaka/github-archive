# typed: true
# frozen_string_literal: true

require "github/null_objects"

class Api::UserPublicKeys < Api::App
  include ReceiveSchemaWithOpenApi
  include PublicKeyHelpers

  # List a User's public keys
  get "/user/keys", operation_id: "users/list-public-ssh-keys-for-authenticated-user" do
    control_access :list_public_keys,
      resource: current_user,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    keys = current_user.public_keys.order(:id)
    keys = paginate_rel(keys)

    deliver :public_key_hash, keys
  end

  # Get a public key
  get "/user/keys/:key_id", operation_id: "users/get-public-ssh-key-for-authenticated-user" do
    @accepted_scopes = %w(admin:public_key read:public_key write:public_key)

    key = find_accessible_key
    control_access :read_public_key,
      resource: key,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    deliver :public_key_hash, key,
      last_modified: calc_last_modified_for_object(current_user)
  end

  # Create (add) public key to a User
  post "/user/keys", operation_id: "users/create-public-ssh-key-for-authenticated-user", read_from_replicas: true do
    control_access :add_public_key,
      resource: current_user,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    if !current_user.change_ssh_key_enabled?
      deliver_update_denied_using_ldap_sync! "SSH keys must be added in the #{GitHub.auth.name} Identity Provider"
    end

    return deliver_user_agent_blocked_error! if user_agent_blocked_from_adding_pubkey? user_agent.string

    # Introducing strict validation of the user-key.create
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    data = receive_with_schema("user-key", "create", skip_validation: true)

    with_write(clusters: [ApplicationRecord::Mysql1]) do
      begin
        public_key = current_user.public_keys.create_with_verification \
          title: data["title"],
          key: data["key"],
          oauth_authorization: current_user.oauth_access&.authorization,
          verifier: current_user

        if !public_key.new_record?
          deliver :public_key_hash, public_key, status: 201
        else
          deliver_error! 422,
            errors: public_key.errors,
            documentation_url: @documentation_url
        end
      rescue ActiveRecord::RecordNotUnique
        deliver_error! 422,
          message: "Validation failed: Key is already in use",
          documentation_url: @documentation_url
      end
    end
  end

  # Delete (remove) public key
  delete "/user/keys/:key_id", operation_id: "users/delete-public-ssh-key-for-authenticated-user" do
    # Introducing strict validation of the user-key.delete
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    receive_with_schema("user-key", "delete", skip_validation: true)

    @accepted_scopes = %w(admin:public_key)

    pk = find_accessible_key

    control_access :remove_public_key,
      resource: pk,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    if !current_user.change_ssh_key_enabled?
      deliver_update_denied_using_ldap_sync! "SSH keys must be removed in the #{GitHub.auth.name} Identity Provider."
    end

    pk.destroy

    deliver_empty(status: 204)
  end

  get "/user/:user_id/keys", operation_id: "users/list-public-keys-for-user" do
    user = find_user!
    control_access :read_user_public, resource: Platform::PublicResource.new(resource: user), allow_integrations: true, allow_user_via_granular_actor: true

    keys = user.verified_keys
    keys = paginate_rel(keys)

    deliver :public_key_hash, keys, simple: true
  end

  private

  def find_accessible_key
    user_id = logged_in? ? current_user.id : 0

    if (key = PublicKey.find_by(user_id: user_id, id: int_id_param!(key: :key_id)))
      key
    else
      GitHub::NullPublicKey.new
    end
  end
end
