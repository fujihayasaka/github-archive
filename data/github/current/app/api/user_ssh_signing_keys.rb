# typed: true
# frozen_string_literal: true

class Api::UserSshSigningKeys < Api::App
  include ReceiveSchemaWithOpenApi

  # List a User's ssh signing keys
  get "/user/ssh_signing_keys", operation_id: "users/list-ssh-signing-keys-for-authenticated-user" do
    control_access :list_ssh_signing_keys,
      resource: current_user,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    keys = current_user.git_signing_ssh_public_keys
    keys = paginate_rel(keys)
    deliver :signing_key_hash, keys
  end

  # Get a ssh signing key
  get "/user/ssh_signing_keys/:ssh_signing_key_id", operation_id: "users/get-ssh-signing-key-for-authenticated-user" do
    key = find_accessible_key

    control_access :read_ssh_signing_key,
      resource: key,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    deliver(:signing_key_hash, key)
  end

  # Create (add) SSH signing key to a User
  post "/user/ssh_signing_keys", operation_id: "users/create-ssh-signing-key-for-authenticated-user" do
    control_access :add_ssh_signing_key,
      resource: current_user,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    data = receive_with_openapi

    signing_key = current_user.git_signing_ssh_public_keys.create \
      title: data["title"],
      key: data["key"]

    if !signing_key.new_record?
      deliver :signing_key_hash, signing_key, status: 201
    else
      deliver_error! 422,
        errors: signing_key.errors,
        documentation_url: @documentation_url
    end
  end

  # Delete (remove) SSH signing key from a User
  delete "/user/ssh_signing_keys/:ssh_signing_key_id", operation_id: "users/delete-ssh-signing-key-for-authenticated-user" do
    signing_key = find_accessible_key
    control_access :remove_ssh_signing_key,
      resource: signing_key,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true


    signing_key.destroy
    deliver_empty(status: 204)
  end

  get "/user/:user_id/ssh_signing_keys", operation_id: "users/list-ssh-signing-keys-for-user" do
    user = find_user!
    control_access :read_user_public,
      resource: Platform::PublicResource.new(resource: user),
      allow_integrations: true,
      allow_user_via_granular_actor: true

    keys = user.git_signing_ssh_public_keys
    keys = paginate_rel(keys)

    deliver(:signing_key_hash, keys)
  end

  private

  def find_accessible_key
    return unless logged_in_as_user?
    GitSigningSshPublicKey.find_by(user_id: current_user.id, id: int_id_param!(key: :ssh_signing_key_id))
  end
end
