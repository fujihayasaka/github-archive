# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module SecretScanning::Features::Owner
  class GenericSecrets
    extend T::Sig

    sig { params(owner: T.any(Organization, Business, User)).void }
    def initialize(owner)
      @owner = owner
      @generic_secrets = if @owner.is_a?(Business)
        SecretScanning::Features::Business::GenericSecrets.new(@owner)
      elsif @owner.is_a?(Organization)
        SecretScanning::Features::Org::GenericSecrets.new(@owner)
      else
        # We don't support Generic Secrets on user-owned repos, this feature always returns false
        SecretScanning::Features::User::GenericSecrets.new(@owner)
      end
    end

    sig { returns(T::Boolean) }
    def enabled_by_owning_business?
      return false unless @owner.is_a?(Organization)
      @generic_secrets.enabled_by_enterprise?
    end

    delegate :feature_available?, :enabled?, :enable, :disable, to: :@generic_secrets
  end
end
