# typed: true
# frozen_string_literal: true

class Codespaces::AdvancedOptions::DeclarativeSecretsTextComponent < ApplicationComponent
  attr_reader :codespace

  def initialize(codespace:, form: nil)
    @codespace = codespace
  end

  memoize def declared_secrets
    secrets = devcontainer&.dig("secrets")
    return unless secrets.present?

    secrets.map do |secret, params|
      {
        name: secret,
        description: params["description"],
        documentation_url: params["documentationUrl"],
      }
    end

  rescue Codespaces::DevContainer::ReadError => e
    # If we failed to read the devcontainer don't raise so we can still render the rest of the page since this
    # is completely optional.
  end

  memoize def existing_user_secrets
    secrets = Codespaces::UserSecret.for(current_user)
    secrets.select { |secret| declared_secrets.any? { |declared_secret| declared_secret[:name] == secret.name } }
  end

  memoize def missing_declared_secrets
    declared_secrets.select { |secret| !existing_secret(secret[:name]) }
  end

  memoize def existing_associated_secrets
    declared_secrets.select { |secret| existing_secret(secret[:name]) && associated_with_repository?(secret[:name]) }
  end

  memoize def existing_unassociated_secrets
    declared_secrets.select { |secret| existing_secret(secret[:name]) && !associated_with_repository?(secret[:name]) }
  end

  def public_key
    Secrets.github_public_key(owner: current_user, key_name: Platform::EncryptionKeys::CODESPACES_SECRETS)
  end

  private

  def render?
    declared_secrets.present?
  end

  def existing_secret(secret_name)
    existing_user_secrets.find { |secret| secret.name == secret_name }
  end

  def associated_with_repository?(secret_name)
    secret = existing_secret(secret_name)
    if secret&.fetch_credential
      return true if secret.repository_ids.include?(@codespace.repository.id)
    end
  end

  memoize def devcontainer
    return unless @codespace.present?

    devcontainer_path = @codespace.devcontainer_path.presence
    ref = @codespace.ref || @codespace.pull_request&.head_ref
    ref_for_oid = Codespaces::GetTargetRef.call(repository: @codespace.repository, name_or_oid: ref) if ref

    if target_oid = ref_for_oid&.target_oid
      Codespaces::DevContainer.new(
        repository: @codespace.repository,
        oid: target_oid,
        filepath: devcontainer_path,
        user: current_user
      )
    end
  end
end
