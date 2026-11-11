# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module SecretScanning::Features::Owner
  # Owner level enablement for validity checks
  class ValidityChecks
    include SecretScanning::Features::FeatureFlagHelper

    sig { params(owner: T.any(Organization, Business, User)).void }
    def initialize(owner)
      @owner = owner
      @validity_checks = if @owner.is_a?(Business)
        SecretScanning::Features::Business::ValidityChecks.new(@owner)
      elsif @owner.is_a?(Organization)
        SecretScanning::Features::Org::ValidityChecks.new(@owner)
      else
        SecretScanning::Features::User::ValidityChecks.new(@owner)
      end
    end

    delegate :feature_available?,
             :enabled_for_new_repos?,
             :enable_for_new_repos,
             :disable_for_new_repos,
             :secret_scanning_enabled_for_new_repos?,
             :enabled?,
             :show_security_config_ux?,
      to: :@validity_checks
  end
end
