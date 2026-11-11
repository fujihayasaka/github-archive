# typed: strict
# frozen_string_literal: true

module SecretScanning::Features::Repo
  class PartnerMetadata
    include SecretScanning::Features::FeatureFlagHelper

    CONFIG_KEY_USER_ENABLED = "token_scanning_partner_metadata.repo.user_enabled"

    sig { params(repo: Repository).void }
    def initialize(repo)
      @validity_checks = T.let(SecretScanning::Features::Repo::ValidityChecks.new(repo), SecretScanning::Features::Repo::ValidityChecks)
      @repo = repo
    end

    sig { returns(T::Boolean) }
    def feature_available?
      return false unless feature_flag_enabled_in_hierarchy?(@repo, FeatureFlags::PARTNER_METADATA)
      return false unless @validity_checks.enabled?
      true
    end

    sig { returns(T::Boolean) }
    def enabled?
      return false unless feature_available?

      config_enabled?
    end

    sig { returns(T::Boolean) }
    def config_enabled?
      @repo.config.enabled?(CONFIG_KEY_USER_ENABLED)
    end

    sig { params(actor: User).void }
    def disable(actor:)
      @repo.config.delete(CONFIG_KEY_USER_ENABLED, actor)
    end

    sig { params(actor: User).void }
    def enable(actor:)
      @repo.config.enable(CONFIG_KEY_USER_ENABLED, actor)
    rescue Configuration::ConflictingRecordError
      # Apparently can happen cuz of a race condition.
      # This error is rare and happens intermittently,
      # so just gonna assume it's weird user behavior and no-op.
    end

    sig { params(token_type: String).returns(T::Boolean) }
    def metadata_for_token_type_explictly_disabled?(token_type)
      flag = "secret_scanning_partner_metadata_disable_for_#{token_type.downcase}"
      feature_flag_enabled_in_hierarchy?(@repo, flag.to_sym)
    end
  end
end
