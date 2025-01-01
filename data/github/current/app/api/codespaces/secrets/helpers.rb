# typed: true
# frozen_string_literal: true

module Api::Codespaces::Secrets::Helpers
  extend T::Sig
  extend T::Helpers

  requires_ancestor { Api::App }

  def validate_non_empty_secret_value!(encrypted_value, owner:)
    decoded = Base64.strict_decode64(encrypted_value || "")
    plaintext_value = DietEarthsmoke::Key.new(Platform::EncryptionKeys::CODESPACES_SECRETS).open(decoded, scope: owner.next_global_id)
    if plaintext_value.empty?
      deliver_error!(422,
        message: "Failed to update secret",
        errors: "value cannot be empty",
        documentation_url: @documentation_url)
    end
  rescue DietEarthsmoke::DietEarthsmokeError, ArgumentError
    # These would mean the value wasn't base64'd or encrypted properly. That will get caught later by kredz.
  end

  # Allows specifying a "secret type" which will potentially change where/how the secret is stored and used.
  # Conventional secrets used within a codespace are referred to as "development_environment" secrets. Additionally,
  # "host_setup" secrets are stored using a different app in Kredz and used alongside the host setup script (Salus beta).
  sig do
    params(
      param: T.nilable(String),
      secret_owner: T.any(User, Organization, Repository)
    ).returns(Symbol)
  end
  def secret_type_param!(param, secret_owner)
    return :development_environment if param.blank? || param == "development_environment"
    if param == "host_setup" && secret_owner.is_a?(Organization) &&
        secret_owner.in_codespaces_salus_beta? &&
        secret_owner.feature_enabled?(:codespaces_host_setup_policy)
      :host_setup
    else
      deliver_error!(422, message: "Invalid secret type")
    end
  end

  sig { params(secret_type: Symbol).returns(Integration) }
  def secrets_app_for_secret_type(secret_type)
    if secret_type == :host_setup
      Apps::Internal.integration(:codespaces_vm_secrets)
    else # :development_environment
      Apps::Internal.integration(:codespaces_production)
    end
  end

  sig { params(secret_type: Symbol).returns(String) }
  def key_name_for_secret_type(secret_type)
    if secret_type == :host_setup
      Platform::EncryptionKeys::CODESPACES_VM_SECRETS
    else # :development_environment
      Platform::EncryptionKeys::CODESPACES_SECRETS
    end
  end
end
