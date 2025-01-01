# typed: true
# frozen_string_literal: true

module SecurityProduct
  class TokenScanningLowerConfidencePatterns < Service
    extend T::Sig

    sig do
      params(repository: Repository).void
    end
    def initialize(repository)
      super(repository)
      @token_scanning_security_product = SecurityProduct::TokenScanning.new(repository)
      @lower_confidence_patterns = SecretScanning::Features::Repo::LowerConfidencePatterns.new(repository)
    end

    sig { returns(T::Boolean) }
    def enabled?
      @lower_confidence_patterns.enabled?
    end

    sig { params(actor: User, options: T.untyped).returns(SecurityProduct::Result) }
    def can_enable?(actor:, options:)
      if blocked_by_enterprise_policy?(actor, options)
        Result.new(false, :token_scanning_restricted_by_enablement_policy)
      elsif !@token_scanning_security_product.enabled?
        Result.new(false, :token_scanning_disabled)
      elsif !SecretScanning::Features::AdvancedSecurityHelper.advanced_security_available?(@repository)
        Result.new(false, :advanced_security_disabled)
      else
        Result.new(true)
      end
    end

    sig { params(actor: User, options: T.untyped).returns(SecurityProduct::Result) }
    def on_enable(actor:, options:)
      @lower_confidence_patterns.enable(actor: actor)
      GitHub.instrument("repository_secret_scanning_non_provider_patterns.enabled", build_instrumentation_payload(actor))
      SecretScanning::Instrumentation::EnablementChangePublisher.publish_enablement_change_event_for_repository(repo: repository)
      GitHub.dogstats.increment("repository_secret_scanning_non_provider_patterns.enabled", tags: dogstats_tags)

      # kick off a backfill
      repository.ensure_low_confidence_backfill_scan_if_enabled(actor: actor)
      Result.new(ToggledServiceCollection.create(to_sym, options))
    end

    sig { params(actor: User, options: T.untyped).returns(SecurityProduct::Result) }
    def force_enable(actor:, options: {})
      on_enable(actor: actor, options: options)
    end

    sig { params(actor: User, options: T.untyped).returns(SecurityProduct::Result) }
    def can_disable?(actor:, options:)
      if !@token_scanning_security_product.can_disable?(actor: actor, options: options).value
        Result.new(false, :token_scanning_restricted_by_enablement_policy)
      else
        Result.new(true)
      end
    end

    sig { params(actor: User, options: T.untyped).returns(SecurityProduct::Result) }
    def on_disable(actor:, options:)
      @lower_confidence_patterns.disable(actor: actor)
      GitHub.instrument("repository_secret_scanning_non_provider_patterns.disabled", build_instrumentation_payload(actor))
      SecretScanning::Instrumentation::EnablementChangePublisher.publish_enablement_change_event_for_repository(repo: repository)
      GitHub.dogstats.increment("repository_secret_scanning_non_provider_patterns.disabled", tags: dogstats_tags)
      Result.new(ToggledServiceCollection.create(to_sym, options))
    end

    sig { params(actor: User, options: T.untyped).returns(SecurityProduct::Result) }
    def force_disable(actor:, options: {})
      on_disable(actor: actor, options: options)
    end

    sig { returns(Symbol) }
    def to_sym
      :token_scanning_lower_confidence_patterns
    end

    sig { returns(String) }
    def self.name
      "Secret scanning lower confidence patterns"
    end

    sig { params(symbol: Symbol).returns(String) }
    def self.error_to_message(symbol)
      case symbol
      when :token_scanning_disabled
        "Secret scanning lower confidence patterns can only be changed on repositories with secret scanning enabled"
      when :token_scanning_restricted_by_enablement_policy
        "Modifying secret scanning and lower confidence patterns has been blocked by an enterprise policy. Contact your enterprise owner for details."
      else
        "Failed to toggle lower confidence patterns enablement"
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
      SecurityProduct::Permissions::RepoAuthz.new(repository, actor:).manage_repo_secret_scanning_settings_blocked_by_policy?
    end
  end
end
