# typed: true
# frozen_string_literal: true

module Platform
  module EncryptionKeys
    CUSTOM_TASKS   = "custom-tasks-key".freeze

    # Used for encrypting codespace secrets before sending them to credz.
    CODESPACES_SECRETS = "codespaces-secrets-key".freeze

    # Used for encrypting codespace host setup secrets before sending them to credz.
    CODESPACES_VM_SECRETS = "codespaces-vm-secrets-key".freeze

    # Used for encrypting Dependabot secrets before sending them to credz.
    DEPENDABOT_SECRETS = "dependabot-secrets-key".freeze

    # Used for encrypting/decrypting private registry secrets.
    PRIVATE_REGISTRY_SECRETS = "private-registry-secrets-key".freeze

    # Used for encrypting/decrypting BYOK custom models secrets for GitHub Models.
    BYOK_CUSTOM_MODELS_SECRETS = "byok-custom-models-secrets-key".freeze

    # Used for encrypting/decrypting bring your own key (BYOK) secrets for Copilot.
    COPILOT_BYOK_SECRETS = "copilot-byok-secrets-key".freeze

    # Used for encrypting/decrypting ELM exporter secrets.
    ELM_EXPORTER_SECRETS = "elm-exporter-secrets-key".freeze
  end
end
