# typed: strict
# frozen_string_literal: true

module SecretScanning::Instrumentation
  # This class builds backend feature flags for instrumentation / service calls for Owners
  # These flags are typically used by Token Scanning Service (TSS)
  class OwnerServiceFlags
    sig { params(owner: T.any(Organization, Business, User)).void }
    def initialize(owner)
      @owner = owner
      @content_scanning = T.let(SecretScanning::Features::Owner::ContentScanning.new(@owner), SecretScanning::Features::Owner::ContentScanning)
      @wiki_scanning = T.let(SecretScanning::Features::Owner::WikiScanning.new(@owner), SecretScanning::Features::Owner::WikiScanning)
      @generic_secrets = T.let(SecretScanning::Features::Owner::GenericSecrets.new(@owner), SecretScanning::Features::Owner::GenericSecrets)
    end

    # Returns service flags for backend instrumentation
    sig { params(config: T.nilable(SecurityConfiguration)).returns(T::Array[String]) }
    def group_backfill_service_flags(config = nil)
      flags = []

      if @content_scanning.enabled?
        flags << ServiceFlags::CONTENT_BACKFILL_SCAN
      end

      if @wiki_scanning.enabled?
        flags << ServiceFlags::WIKI_INCREMENTAL_SCANS
        flags << ServiceFlags::WIKI_BACKFILL_SCANS
      end

      if include_generic_secrets?(config)
        flags << ServiceFlags::GENERIC_SECRETS_SCAN
      end

      flags
    end

    sig { params(config: T.nilable(SecurityConfiguration)).returns(T::Boolean) }
    def include_generic_secrets?(config)
      if !config.nil? && @owner.feature_flag_enabled?(SecretScanning::Features::FeatureFlagHelper::FeatureFlags::GENERIC_SECRETS_IN_SECURITY_CONFIGURATIONS, default: true)
        return config.secret_scanning_generic_secrets_enabled?
      end

      @generic_secrets.enabled?
    end
  end
end
