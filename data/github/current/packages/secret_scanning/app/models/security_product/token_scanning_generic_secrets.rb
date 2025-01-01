# typed: true
# frozen_string_literal: true

module SecurityProduct
  class TokenScanningGenericSecrets < Service
    extend T::Sig

    sig do
      params(repository: Repository).void
    end
    def initialize(repository)
      super(repository)
      @token_scanning_security_product = SecurityProduct::TokenScanning.new(repository)
      @generic_secrets = SecretScanning::Features::Repo::GenericSecrets.new(repository)
    end

    sig { returns(T::Boolean) }
    def enabled?
      @generic_secrets.enabled?
    end

    # Enablement of this service depends entirely on TokenScanning being able to be enabled
    sig { params(actor: User, options: T.untyped).returns(SecurityProduct::Result) }
    def can_enable?(actor:, options:)
      if blocked_by_enterprise_policy?(actor, options)
        Result.new(false, :token_scanning_restricted_by_enablement_policy)
      elsif !@token_scanning_security_product.enabled?
        Result.new(false, :token_scanning_disabled)
      else
        Result.new(true)
      end
    end

    sig { params(actor: User, options: T.untyped).returns(SecurityProduct::Result) }
    def on_enable(actor:, options:)
      @generic_secrets.enable(actor: actor)

      GitHub.instrument("repository_secret_scanning_generic_secrets.enabled", build_instrumentation_payload(actor))
      SecretScanning::Instrumentation::EnablementChangePublisher.publish_enablement_change_event_for_repository(repo: repository)
      GitHub.dogstats.increment("repository_secret_scanning_generic_secrets.enabled", tags: dogstats_tags)

      # kick off a backfill
      repository.ensure_generic_secrets_backfill_scan_if_enabled(actor: actor)

      Result.new(ToggledServiceCollection.create(to_sym, options))
    end

    sig { params(actor: User, options: T.untyped).returns(SecurityProduct::Result) }
    def force_enable(actor:, options: {})
      on_enable(actor: actor, options: options)
    end

    sig { params(actor: User, options: T.untyped).returns(SecurityProduct::Result) }
    def can_disable?(actor:, options:)
      if blocked_by_enterprise_policy?(actor, options)
        Result.new(false, :token_scanning_restricted_by_enablement_policy)
      else
        Result.new(true)
      end
    end

    sig { params(actor: User, options: T.untyped).returns(SecurityProduct::Result) }
    def on_disable(actor:, options:)
      @generic_secrets.disable(actor: actor)

      GitHub.instrument("repository_secret_scanning_generic_secrets.disabled", build_instrumentation_payload(actor))
      SecretScanning::Instrumentation::EnablementChangePublisher.publish_enablement_change_event_for_repository(repo: repository)
      GitHub.dogstats.increment("repository_secret_scanning_generic_secrets.disabled", tags: dogstats_tags)

      Result.new(ToggledServiceCollection.create(to_sym, options))
    end

    sig { params(actor: User, options: T.untyped).returns(SecurityProduct::Result) }
    def force_disable(actor:, options: {})
      on_disable(actor: actor, options: options)
    end

    sig { returns(Symbol) }
    def to_sym
      :token_scanning_generic_secrets
    end

    sig { returns(String) }
    def self.name
      "Secret scanning AI detection"
    end

    sig { params(symbol: Symbol).returns(String) }
    def self.error_to_message(symbol)
      case symbol
      when :token_scanning_disabled
        "Usage of an AI model to find can only be toggled on repositories with secret scanning enabled"
      when :token_scanning_restricted_by_enablement_policy
        "Configuration of Secret Scanning has been blocked by an enterprise policy. Contact your enterprise owner for details."
      else
        "Failed to toggle enablement of usage of an AI model to find secrets"
      end
    end

    private

    def build_instrumentation_payload(actor)
      payload = {
        actor: actor,
        repo: repository
      }

      if repository.in_organization?
        payload[:org] = repository.organization
      end

      payload
    end

    def dogstats_tags
      [
        "visibility:#{repository.visibility}",
        "ghas_secret_scanning:#{SecretScanning::Features::Repo::Capabilities.new(repository).ghas_secret_scanning?}",
      ]
    end

    # Checks if toggling restricted by Configurable::SecretScanningSettingsPolicy
    sig { params(actor: User, options: T.untyped).returns(T::Boolean) }
    def blocked_by_enterprise_policy?(actor, options)
      return false if options.present? && options[:is_repo_creation]
      return true if repository.business.present? && !repository.business.repo_admins_can_modify_generic_secrets_settings?
      false
    end
  end
end
