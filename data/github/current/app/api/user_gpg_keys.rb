# typed: true
# frozen_string_literal: true

class Api::UserGpgKeys < Api::App
  include ReceiveSchemaWithOpenApi

  # List a User's GPG keys
  get "/user/gpg_keys", operation_id: "users/list-gpg-keys-for-authenticated-user" do
    control_access :list_gpg_keys,
      resource: current_user,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    keys = current_user.gpg_keys.primary_keys.with_subkeys.with_emails.
      includes([:emails, { user: { business_user_accounts: :business } }])
    keys = paginate_rel(keys)

    deliver(:gpg_key_hash, keys)
  end

  # Get a GPG key
  get "/user/gpg_keys/:gpg_key_id", operation_id: "users/get-gpg-key-for-authenticated-user" do
    key = GpgKey.with_subkeys.where(id: int_id_param!(key: :gpg_key_id)).
      includes([:emails, { user: { business_user_accounts: :business } }]).
      first

    control_access :read_gpg_key,
      resource: key,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    deliver(:gpg_key_hash, key)
  end

  # Create (add) GPG key to a User
  post "/user/gpg_keys", operation_id: "users/create-gpg-key-for-authenticated-user" do
    control_access :add_gpg_key,
      resource: current_user,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    if !current_user.change_gpg_key_enabled?
      deliver_update_denied_using_ldap_sync! "GPG keys must be added in the #{GitHub.auth.name} Identity Provider"
    end

    data = receive_with_openapi

    armored_public_key = data["armored_public_key"].to_s
    name = data["name"].to_s
    key = current_user.gpg_keys.create_from_armored_public_key(
      armored_public_key,
      name: name,
      accept_revoked_keys: true
    )

    if !key.new_record?
      deliver(:gpg_key_hash, key, status: 201)
    else
      deliver_error(422,
        errors: key.errors,
        documentation_url: "/v3/users/gpg_keys",
      )
    end
  end

  # Delete (remove) GPG key
  delete "/user/gpg_keys/:gpg_key_id", operation_id: "users/delete-gpg-key-for-authenticated-user" do
    receive_with_schema("gpg-key", "delete")

    key = GpgKey.where(id: int_id_param!(key: :gpg_key_id)).first
    control_access :remove_gpg_key,
      resource: key,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    if !current_user.change_gpg_key_enabled?
      deliver_update_denied_using_ldap_sync! "GPG keys must be removed in the #{GitHub.auth.name} Identity Provider."
    end

    if T.must(key).subkey?
      message = "Subkeys cannot be deleted directly. Delete the primary key "\
        "instead."
      deliver_error(
        422,
        message: message,
        documentation_url: "/v3/users/gpg_keys",
      )
    else
      T.must(key).destroy
      deliver_empty(status: 204)
    end
  end

  get "/user/:user_id/gpg_keys", operation_id: "users/list-gpg-keys-for-user" do
    user = find_user!
    control_access :read_user_public,
      resource: Platform::PublicResource.new(resource: user),
      allow_integrations: true,
      allow_user_via_granular_actor: true

    keys = user.gpg_keys.primary_keys.with_subkeys.with_emails.
      includes([:emails, { user: { business_user_accounts: :business } }])
    keys = paginate_rel(keys)

    deliver(:gpg_key_hash, keys)
  end
end
