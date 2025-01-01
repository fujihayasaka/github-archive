# typed: strict
# frozen_string_literal: true

module SecurityProduct
  class TokenScanningValidityChecks < Service
    sig do
      params(repository: Repository).void
    end
    def initialize(repository)
      super(repository)
      @token_scanning_security_product = T.let(SecurityProduct::TokenScanning.new(repository), SecurityProduct::TokenScanning)
      @validity_checks = T.let(SecretScanning::Features::Repo::ValidityChecks.new(repository), SecretScanning::Features::Repo::ValidityChecks)
    end

    sig { override.returns(T::Boolean) }
    def enabled?
      @validity_checks.enabled?
    end

    # Enablement of this service depends entirely on TokenScanning being able to be enabled
    sig { override.params(actor: User, options: T.untyped).returns(SecurityProduct::Result) }
    def can_enable?(actor:, options:)
      if blocked_by_enterprise_policy?(actor, options)
        Result.new(false, :token_scanning_restricted_by_enablement_policy)
      elsif !@token_scanning_security_product.enabled?
        Result.new(false, :token_scanning_disabled)
      else
        Result.new(true)
      end
    end

    sig { override.params(actor: User, options: T.untyped).returns(SecurityProduct::Result) }
    def on_enable(actor:, options:)
      return Result.new(ToggledServiceCollection.empty) unless @validity_checks.feature_available?
      @validity_checks.enable(actor: actor)

      payload = { user: actor, repo: repository, org: repository.organization }
      GitHub.instrument("repository_secret_scanning_automatic_validity_checks.enabled", payload)
      SecretScanning::Instrumentation::EnablementChangePublisher.publish_enablement_change_event_for_repository(repo: repository)

      Result.new(ToggledServiceCollection.create(to_sym, options))
    end

    sig { params(actor: User, options: T.untyped).returns(SecurityProduct::Result) }
    def force_enable(actor:, options: {})
      on_enable(actor: actor, options: options)
    end

    sig { override.params(actor: User, options: T.untyped).returns(SecurityProduct::Result) }
    def can_disable?(actor:, options:)
      if blocked_by_enterprise_policy?(actor, options)
        Result.new(false, :token_scanning_restricted_by_enablement_policy)
      else
        Result.new(true)
      end
    end

    sig { override.params(actor: User, options: T.untyped).returns(SecurityProduct::Result) }
    def on_disable(actor:, options:)
      @validity_checks.disable(actor: actor)

      payload = { user: actor, repo: repository, org: repository.organization }
      GitHub.instrument("repository_secret_scanning_automatic_validity_checks.disabled", payload)
      SecretScanning::Instrumentation::EnablementChangePublisher.publish_enablement_change_event_for_repository(repo: repository)

      Result.new(ToggledServiceCollection.create(to_sym, options))
    end

    sig { params(actor: User, options: T.untyped).returns(SecurityProduct::Result) }
    def force_disable(actor:, options: {})
      on_disable(actor: actor, options: options)
    end

    sig { override.returns(Symbol) }
    def to_sym
      :token_scanning_validity_checks
    end

    sig { override.returns(String) }
    def self.name
      "Secret scanning Validity Checks"
    end

    sig { override.params(symbol: T.nilable(SecurityProduct::Result::Error)).returns(String) }
    def self.error_to_message(symbol)
      case symbol
      when :token_scanning_disabled
        "Secret scanning validity checks can only be changed on repositories with secret scanning enabled"
      when :token_scanning_restricted_by_enablement_policy
        "Modifying Secret scanning and validity checks has been blocked by an enterprise policy. Contact your enterprise owner for details."
      else
        "Failed to toggle validity checks enablement"
      end
    end

    private

    # Checks if toggling restricted by Configurable::SecretScanningSettingsPolicy
    sig { params(actor: User, options: T.untyped).returns(T::Boolean) }
    def blocked_by_enterprise_policy?(actor, options)
      return false if options.present? && options[:is_repo_creation]
      SecurityProduct::Permissions::RepoAuthz.new(repository, actor:).manage_repo_secret_scanning_settings_blocked_by_policy?
    end
  end
end
