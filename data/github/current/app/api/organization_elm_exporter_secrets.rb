# typed: true
# frozen_string_literal: true

require "github/kredz_client"

class Api::OrganizationElmExporterSecrets < Api::App
  include Api::App::CryptoKeyHelper
  include Api::App::CredzSecretsHelper
  include Api::App::SecretsHelpers
  include GitHub::KredzClient
  include ReceiveSchemaWithOpenApi

  ALLOWED_SECRET_NAMES = %w[SOURCE_PAT TARGET_PAT].freeze

  get "/organizations/:organization_id/elm-exporter/secrets/public-key", operation_id: "elm-exporter/get-org-public-key" do
    org = find_org!
    deliver_error! 404 unless elm_exporter_secrets_enabled?

    # These endpoints are for *human* management of ELM exporter secrets: org
    # admins and holders of the `organization_elm_exporter_secrets` fine-grained
    # permission set/manage the values that the privileged `elm_exporter_secrets`
    # integration consumes at runtime (the exporter reads secret *values*
    # out-of-band via that integration's own secret store, never through this
    # API).
    #
    # We therefore deliberately do NOT grant arbitrary GitHub App
    # server-to-server installations access via the generic
    # `organization_elm_exporter_secrets` permission set (`allow_integrations: false`);
    # only user-attributed granular actors (FGP via PAT v2 / user-to-server) and
    # org admins (OAuth `admin:org` / web) may manage these secrets.
    control_access :read_elm_exporter_secrets_org,
      resource: org,
      forbid: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    public_key = if GitHub.enterprise?
      { key_identifier: "1", key: GitHub.actions_secrets_public_key }
    else
      generate_diet_earthsmoke_key_payload(name: Platform::EncryptionKeys::ELM_EXPORTER_SECRETS, scope: org.next_global_id)
    end

    payload = { key_id: public_key[:key_identifier], key: public_key[:key] }

    deliver_raw(payload)
  end

  get "/organizations/:organization_id/elm-exporter/secrets/:name", operation_id: "elm-exporter/get-org-secret" do
    org = find_org!
    deliver_error! 404 unless elm_exporter_secrets_enabled?
    validate_secret_name!

    # Metadata-only read for human secret management (see the public-key endpoint
    # above). This endpoint never returns decrypted secret values, and arbitrary
    # GitHub App server-to-server installations are not permitted
    # (`allow_integrations: false`).
    control_access :read_elm_exporter_secrets_org,
      resource: org,
      forbid: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    result = rescue_from_secrets_errors do
      Secrets.fetch(
        name: params[:name],
        app: Apps::Privileged.integration(:elm_exporter_secrets),
        owner: org,
        actor: current_user,
      )
    end

    deliver_error! 404 unless result

    deliver :elm_exporter_org_secret_hash, { secret: result.credential, org: org }
  end

  put "/organizations/:organization_id/elm-exporter/secrets/:name", operation_id: "elm-exporter/create-or-update-org-secret", read_from_replicas: false do
    org = find_org!
    deliver_error! 404 unless elm_exporter_secrets_enabled?
    validate_secret_name!

    # Humans configure these secrets; the privileged `elm_exporter_secrets`
    # integration only reads their values at runtime (out-of-band). Arbitrary
    # GitHub App server-to-server installations must not be able to write them
    # via the generic permission set (`allow_integrations: false`).
    control_access :write_elm_exporter_secrets_org,
      resource: org,
      forbid: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    data = receive_with_openapi
    value = data["encrypted_value"]
    key_identifier = data["key_id"]

    validation = Credz.validate_org_secret(params[:name], value, GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_PRIVATE_REPOS)
    unless validation.succeeded?
      deliver_error! 422, message: validation.error, documentation_url: @documentation_url
    end

    value = if GitHub.enterprise?
      decrypt_enterprise_value(value)
    else
      pack_earthsmoke_value(Platform::EncryptionKeys::ELM_EXPORTER_SECRETS, key_identifier, value)
    end

    encoded_value = Base64.strict_encode64(value)

    result = rescue_from_secrets_errors do
      Secrets.store(
        name: params[:name],
        app: Apps::Privileged.integration(:elm_exporter_secrets),
        owner: org,
        actor: current_user,
        value: encoded_value,
        visibility: GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_PRIVATE_REPOS,
      )
    end

    validate_result!(result)
    validate_storage!(result)

    status = 201
    if result.updated
      status = 204
    end

    deliver_empty(status: status)
  end

  private

  def elm_exporter_secrets_enabled?
    GitHub.elm_exporter_enabled?
  end

  def validate_secret_name!
    unless ALLOWED_SECRET_NAMES.include?(params[:name])
      deliver_error! 422, message: "Secret name must be one of: #{ALLOWED_SECRET_NAMES.join(', ')}"
    end
  end
end
