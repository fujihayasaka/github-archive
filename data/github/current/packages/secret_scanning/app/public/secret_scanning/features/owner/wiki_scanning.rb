# typed: strict
# frozen_string_literal: true

module SecretScanning::Features::Owner
  # Owner level enablement for Issue Scanning
  class WikiScanning
    include SecretScanning::Features::FeatureFlagHelper

    Owner = T.type_alias { T.any(Organization, Business, User) }
    TokenScanning = T.type_alias { T.any(SecretScanning::Features::Business::TokenScanning, SecretScanning::Features::Org::TokenScanning, SecretScanning::Features::User::TokenScanning) }
    PublicScanning = T.type_alias { T.any(SecretScanning::Features::Business::PublicScanning, SecretScanning::Features::Org::PublicScanning, SecretScanning::Features::User::PublicScanning) }

    sig { params(owner: Owner).void }
    def initialize(owner)
      @owner = owner
      @token_scanning = T.let(token_scanning(owner), TokenScanning)
      @public_scanning = T.let(public_scanning(owner), PublicScanning)
    end

    sig { params(owner: Owner).returns(TokenScanning) }
    def token_scanning(owner)
      return SecretScanning::Features::Business::TokenScanning.new(owner) if owner.is_a?(Business)
      return SecretScanning::Features::Org::TokenScanning.new(owner) if owner.is_a?(Organization)
      SecretScanning::Features::User::TokenScanning.new(owner)
    end

    sig { params(owner: Owner).returns(PublicScanning) }
    def public_scanning(owner)
      return SecretScanning::Features::Business::PublicScanning.new(owner) if owner.is_a?(Business)
      return SecretScanning::Features::Org::PublicScanning.new(owner) if owner.is_a?(Organization)
      SecretScanning::Features::User::PublicScanning.new(owner)
    end

    sig { returns(T::Boolean) }
    def feature_available?
      # GHES not yet supported; once it is, we can check GitHub.secret_scanning_for_all_content_types_enabled config setting
      return false if GitHub.enterprise?

      @public_scanning.enabled? || @token_scanning.enabled?
    end

    sig { returns(T::Boolean) }
    def enabled?
      # feature flag checks
      return false unless self.incremental_enabled?
      return false unless self.backfill_enabled?

      # Always enabled if available
      self.feature_available?
    end

    sig { returns(T::Boolean) }
    def incremental_enabled?
      feature_flag_enabled?(@owner, FeatureFlags::WIKI_INCREMENTAL_SCANS)
    end

    sig { returns(T::Boolean) }
    def backfill_enabled?
      feature_flag_enabled?(@owner, FeatureFlags::WIKI_BACKFILL_SCANS)
    end
  end
end
