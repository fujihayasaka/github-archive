# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module SecretScanning::Features::Owner
  # Org level enablement for Push Protection
  class TokenScanning
    include SecretScanning::Features::FeatureFlagHelper

    sig { params(owner: T.any(Organization, Business, User)).void }
    def initialize(owner)
      @owner = owner
      @token_scanning = if @owner.is_a?(Business)
        SecretScanning::Features::Business::TokenScanning.new(@owner)
      elsif @owner.organization?
        SecretScanning::Features::Org::TokenScanning.new(@owner)
      else
        SecretScanning::Features::User::TokenScanning.new(@owner)
      end
    end

    delegate :feature_available?,
             :can_enable_for_new_repos?,
             :secret_scanning_enabled_for_new_repos?,
      to: :@token_scanning
  end
end
