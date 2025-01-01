# typed: true
# frozen_string_literal: true

class Api::OrganizationPrivateRegistries < Api::App
  include Api::App::CredzSecretsHelper
  include Api::App::SecretsHelpers
  include Api::App::CryptoKeyHelper
  include FeatureFlagHelper

  ORG_PRIVATE_REGISTRIES_FORBIDDEN_MESSAGE = "You must be an org admin or have the org private registries fine-grained permission."

  get "/organizations/:organization_id/private-registries", operation_id: "private-registries/list-org-private-registries" do
    org = find_org!

    control_access :read_org_private_registries,
      resource: org,
      forbid: true,
      forbid_message: ORG_PRIVATE_REGISTRIES_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    result = rescue_from_secrets_errors do
      ::Secrets.list(
        app: private_registry_app,
        owner: org,
        actor: current_user,
      )
    end

    validate_listing!(result)

    paginated_configs = paginate_rel(PrivateRegistry::Configuration.for_organization(org))
    config_data = paginated_configs.map { |c| [c.secret_name, c] }.to_h
    secrets = result.credentials.to_a.select { |secret| config_data.keys.include?(secret.name) }

    deliver(:org_private_registries_hash, {
      config_data:,
      org:,
      secrets:,
      total_count: paginated_configs.total_entries,
    })
  end

  # KEEP THIS DEFINITION ABOVE GET SECRET - otherwise this endpoint will fall through.
  get "/organizations/:organization_id/private-registries/public-key", operation_id: "private-registries/get-org-public-key" do
    org = find_org!

    control_access :read_org_private_registries,
      resource: org,
      forbid: true,
      forbid_message: ORG_PRIVATE_REGISTRIES_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    public_key = if GitHub.enterprise?
      { key_identifier: "1", key: GitHub.actions_secrets_public_key }
    else
      generate_diet_earthsmoke_key_payload(name: Platform::EncryptionKeys::PRIVATE_REGISTRY_SECRETS, scope: org.next_global_id)
    end

    payload = { key_id: public_key[:key_identifier], key: public_key[:key] }

    deliver_raw(payload)
  end

  get "/organizations/:organization_id/private-registries/:secret_name", operation_id: "private-registries/get-org-private-registry" do
    org = find_org!

    control_access :read_org_private_registries,
      resource: org,
      forbid: true,
      forbid_message: ORG_PRIVATE_REGISTRIES_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    config_data = PrivateRegistry::Configuration.for_organization(org).find_by(secret_name: params[:secret_name])
    deliver_error! 404 if config_data.blank?

    result = rescue_from_secrets_errors do
      ::Secrets.fetch(name: config_data.secret_name,
        owner: org,
        actor: current_user,
        app: private_registry_app)
    end

    validate_listing!(result)
    deliver_error! 404 if result.error.present?

    deliver(:org_private_registry_hash, {
      config_data:,
      org:,
      secret: result.credential,
    })
  end

  post "/organizations/:organization_id/private-registries", operation_id: "private-registries/create-org-private-registry" do
    org = find_org!

    control_access :write_org_private_registries,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true,
      forbid: true,
      forbid_message: ORG_PRIVATE_REGISTRIES_FORBIDDEN_MESSAGE

    request_data = receive_with_openapi  # Validate request body against OpenAPI schema
    attributes = attr(
      request_data,
      :registry_type,
      :url,
      :username,
      :encrypted_value,
      :key_id,
      :visibility,
      :selected_repository_ids,
    )

    registry_types = available_registry_types(org: org)
    unless registry_types.include?(attributes[:registry_type])
      deliver_error! 422,
        message: "Failed to create private registry configuration",
        errors: ["registry_type must be one of: #{registry_types.join(", ")}"],
        documentation_url: @documentation_url
    end

    secret_name = "#{attributes[:registry_type].upcase}_SECRET"
    visibility = GitHub::KredzClient::Credz::FROM_VISIBILITY_MAP[attributes[:visibility]]

    validate_secret_attributes!(
      secret_name: secret_name,
      encrypted_value: attributes[:encrypted_value],
      visibility: visibility,
      owner: org,
    )

    selected_repositories = []
    if visibility == GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_SELECTED_REPOS
      unless attributes.key?(:selected_repository_ids)
        deliver_error! 422,
          message: "selected_repository_ids is required when visibility is 'selected'",
          documentation_url: @documentation_url
      end

      selected_repository_ids = attributes[:selected_repository_ids].to_set
      selected_repositories = org.repositories.where(id: selected_repository_ids).map(&:global_relay_id)
    end

    value = if GitHub.enterprise?
      decrypt_enterprise_value(attributes[:encrypted_value])
    else
      pack_earthsmoke_value(private_registry_key_name, attributes[:key_id], attributes[:encrypted_value])
    end
    encoded_value = Base64.strict_encode64(value)

    result = rescue_from_secrets_errors do
      Secrets.create(
        name: secret_name,
        app: private_registry_app,
        owner: org,
        actor: current_user,
        value: encoded_value,
        visibility: visibility,
        selected_repositories: selected_repositories,
      )
    end
    validate_result!(result)
    validate_storage!(result)

    configuration = PrivateRegistry::Configuration.new(
      owner: org,
      owner_type: "Organization",
      registry_type: attributes[:registry_type],
      secret_name: secret_name,
      url: attributes[:url],
      username: attributes[:username],
    )
    begin
      configuration.save!
    rescue ActiveRecord::ActiveRecordError => e
      # There was an error saving the configuration record so we should delete the secret
      rescue_from_secrets_errors do
        Secrets.delete(name: secret_name, owner: org, actor: current_user, app: private_registry_app)
      end

      errors = e.record.errors if e.is_a?(ActiveRecord::RecordInvalid) || e.is_a?(ActiveRecord::RecordNotSaved)

      deliver_error! 422,
        message: "Failed to create private registry configuration",
        errors: errors,
        documentation_url: @documentation_url
    end

    # We can't deliver an empty response (i.e., we need to return the configuration) because we generate the
    # secret name and that secret name is a required path parameter for the get/update/delete endpoints.
    deliver :org_private_registry_hash, {
      config_data: configuration,
      org: org,
      secret: result.credential,
    }, status: 201
  end

  patch "/organizations/:organization_id/private-registries/:secret_name", operation_id: "private-registries/update-org-private-registry" do
    org = find_org!

    control_access :write_org_private_registries,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true,
      forbid: true,
      forbid_message: ORG_PRIVATE_REGISTRIES_FORBIDDEN_MESSAGE

    secret_name = params[:secret_name]

    request_data = receive_with_openapi  # Validate request body against OpenAPI schema
    attributes = attr(
      request_data,
      :registry_type,
      :url,
      :username,
      :encrypted_value,
      :key_id,
      :visibility,
      :selected_repository_ids,
    )

    configuration = PrivateRegistry::Configuration.for_organization(org).find_by(secret_name: secret_name)
    deliver_error! 404 unless configuration

    fetch_result = rescue_from_secrets_errors do
      Secrets.fetch(
        name: configuration.secret_name,
        owner: org,
        actor: current_user,
        app: private_registry_app,
      )
    end
    validate_result!(fetch_result)
    deliver_error! 404 if fetch_result.error || !fetch_result.credential

    secret = fetch_result.credential
    visibility = secret.visibility

    secret_kwargs = {
      name: secret_name,
      app: private_registry_app,
      owner: org,
      actor: current_user,
    }

    if attributes[:visibility]
      visibility = GitHub::KredzClient::Credz::FROM_VISIBILITY_MAP[attributes[:visibility]]
      validate_visibility!(visibility)
    end
    secret_kwargs[:visibility] = visibility

    if visibility == GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_SELECTED_REPOS
      selected_repository_ids = if attributes[:selected_repository_ids]
        attributes[:selected_repository_ids].to_set
      else
        secret.selected_repositories.map { |repo| Platform::Helpers::NodeIdentification.from_global_id(repo.global_id)[1] }
      end
      secret_kwargs[:selected_repositories] = org.repositories.where(id: selected_repository_ids).map(&:global_relay_id)
    end

    if attributes[:encrypted_value]
      validate_encrypted_value!(secret_name: secret_name, encrypted_value: attributes[:encrypted_value], owner: org)

      value = if GitHub.enterprise?
        decrypt_enterprise_value(attributes[:encrypted_value])
      else
        pack_earthsmoke_value(private_registry_key_name, attributes[:key_id], attributes[:encrypted_value])
      end
      secret_kwargs[:value] = Base64.strict_encode64(value)
    end

    update_result = rescue_from_secrets_errors { Secrets.update(**secret_kwargs) }
    validate_result!(update_result)

    configuration_attributes = {}
    configuration_attributes[:registry_type] = attributes[:registry_type] if attributes[:registry_type]
    configuration_attributes[:url] = attributes[:url] if attributes[:url]
    configuration_attributes[:username] = attributes[:username] if attributes.key?(:username)

    begin
      configuration.update!(configuration_attributes) if configuration_attributes.any?
    rescue ActiveRecord::ActiveRecordError => e
      errors = e.record.errors if e.is_a?(ActiveRecord::RecordInvalid) || e.is_a?(ActiveRecord::RecordNotSaved)

      deliver_error! 422,
        message: "Failed to update private registry configuration",
        errors: errors,
        documentation_url: @documentation_url
    end

    deliver_empty(status: 204)
  end

  delete "/organizations/:organization_id/private-registries/:secret_name", operation_id: "private-registries/delete-org-private-registry" do
    org = find_org!

    control_access :write_org_private_registries,
      resource: org,
      forbid: true,
      forbid_message: ORG_PRIVATE_REGISTRIES_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    private_registry_config = PrivateRegistry::Configuration.for_organization(org).find_by(secret_name: params[:secret_name])

    deliver_error! 404 unless private_registry_config.present?

    private_registry_config.destroy!

    result = rescue_from_secrets_errors(-> (_e) { PrivateRegistry::Configuration.new(private_registry_config.attributes).save! }) do
      Secrets.delete(
        name: params[:secret_name],
        app: Secrets::AppsHelper.app_for("private_registries", current_user, org: org),
        owner: org,
        actor: current_user,
      )
    end

    deliver_empty status: (result&.success ? 204 : 404)
  end

  private

  def private_registry_app
    @private_registry_app ||= Apps::Privileged.integration(:private_registry_secrets)
  end

  def private_registry_key_name
    Platform::EncryptionKeys::PRIVATE_REGISTRY_SECRETS
  end

  def available_registry_types(org:)
    PrivateRegistry::Configuration.registry_types.keys
  end

  def validate_secret_attributes!(secret_name:, encrypted_value:, visibility:, owner:)
    validate_encrypted_value!(secret_name: secret_name, encrypted_value: encrypted_value, owner: owner)
    validate_visibility!(visibility)
  end

  def validate_encrypted_value!(secret_name:, encrypted_value:, owner:)
    deliver_error! 422, message: "encrypted_value cannot be blank", documentation_url: @documentation_url if encrypted_value.blank?

    plaintext_value = if GitHub.enterprise?
      decrypt_enterprise_value(encrypted_value)
    else
      DietEarthsmoke::Key.new(private_registry_key_name).open(Base64.strict_decode64(encrypted_value), scope: owner.next_global_id)
    end
    deliver_error! 422, message: "encrypted_value cannot be blank", documentation_url: @documentation_url if plaintext_value.blank?

    validation = GitHub::KredzClient::Credz.validate_secret(secret_name, encrypted_value)
    deliver_error! 422, message: validation.error, documentation_url: @documentation_url unless validation.succeeded
  rescue DietEarthsmoke::DietEarthsmokeError, ArgumentError
    # An error here means encrypted_value wasn't base64-encoded or encrypted properly.
    # This will get caught later by kredz.
  end

  def validate_visibility!(visibility)
    unless GitHub::KredzClient::Credz::VALID_CREDENTIAL_VISIBILITIES.include?(visibility)
      deliver_error! 422, message: "Unknown visibility", documentation_url: @documentation_url
    end
  end
end
