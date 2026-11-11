# typed: strict
# frozen_string_literal: true

module SecurityProduct
  class TokenScanningPartnerMetadata < Service
    sig { params(repository: Repository).void }
    def initialize(repository)
      super(repository)
      @partner_metadata = T.let(SecretScanning::Features::Repo::PartnerMetadata.new(repository), SecretScanning::Features::Repo::PartnerMetadata)
    end


    sig { override.returns(T::Boolean) }
    def enabled?
      @partner_metadata.enabled?
    end

    sig { override.params(actor: User, options: T.untyped).returns(SecurityProduct::Result) }
    def can_enable?(actor:, options:)
      if blocked_by_enterprise_policy?(actor, options)
        return Result.new(false, :token_scanning_restricted_by_enablement_policy)
      end
      @partner_metadata.feature_available? ? Result.new(true) : Result.new(false, :token_scanning_partner_metadata_unavailable) # feature_available checks if validity checks are enabled
    end

    sig { override.params(actor: User, options: T.untyped).returns(SecurityProduct::Result) }
    def can_disable?(actor:, options:)
      if blocked_by_enterprise_policy?(actor, options)
        Result.new(false, :token_scanning_restricted_by_enablement_policy)
      else
        Result.new(true)
      end
    end

    sig do
      override
      .params(
        actor: User,
        options: T.untyped
      )
      .returns(SecurityProduct::Result)
    end
    def on_disable(actor:, options:)
      @partner_metadata.disable(actor: actor)

      if FeatureFlag.vexi.enabled?(SecretScanning::Features::FeatureFlagHelper::FeatureFlags::REPOSITORY_SECRET_SCANNING_EXTENDED_METADATA_AUDIT_LOG, repository, default: false)
        payload = { user: actor, repo: repository, org: repository.organization }
        GitHub.instrument("repository_secret_scanning_extended_metadata.disabled", payload)
      end

      Result.new(ToggledServiceCollection.create(to_sym, options))
    end

    sig do
      override
      .params(
        actor: User,
        options: T.untyped
      )
      .returns(SecurityProduct::Result)
    end
    def on_enable(actor:, options:)
      return Result.new(ToggledServiceCollection.empty) unless @partner_metadata.feature_available?
      @partner_metadata.enable(actor: actor)

      if FeatureFlag.vexi.enabled?(SecretScanning::Features::FeatureFlagHelper::FeatureFlags::REPOSITORY_SECRET_SCANNING_EXTENDED_METADATA_AUDIT_LOG, repository, default: false)
        payload = { user: actor, repo: repository, org: repository.organization }
        GitHub.instrument("repository_secret_scanning_extended_metadata.enabled", payload)
      end

      Result.new(ToggledServiceCollection.create(to_sym, options))
    end

    sig { override.returns(Symbol) }
    def to_sym
      :token_scanning_partner_metadata
    end

    sig { override.params(symbol: T.nilable(SecurityProduct::Result::Error)).returns(String) }
    def self.error_to_message(symbol)
      case symbol
      when :token_scanning_restricted_by_enablement_policy
        "Modifying Secret scanning and partner metadata has been blocked by an enterprise policy. Contact your enterprise owner for details."
      else
        "Failed to toggle partner metadata enablement"
      end
    end

    private

    # Checks if toggling restricted by Configurable::SecretScanningSettingsPolicy
    sig { params(actor: User, options: T.untyped).returns(T::Boolean) }
    def blocked_by_enterprise_policy?(actor, options)
      return false if options.present? && (options[:is_repo_creation] || options[:is_repo_unarchived])
      SecurityProduct::Permissions::RepoAuthz.new(repository, actor:).manage_repo_secret_scanning_settings_blocked_by_policy?
    end

  end
end
