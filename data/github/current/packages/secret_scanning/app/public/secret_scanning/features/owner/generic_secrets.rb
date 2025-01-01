# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module SecretScanning::Features::Owner
  class GenericSecrets
    sig { params(owner: T.any(Organization, Business, User)).void }
    def initialize(owner)
      @owner = owner
      @generic_secrets = T.let(
        case @owner
        when Business then SecretScanning::Features::Business::GenericSecrets.new(@owner)
        when Organization then SecretScanning::Features::Org::GenericSecrets.new(@owner)
        when User then SecretScanning::Features::User::GenericSecrets.new(@owner)
        else T.absurd(@owner)
        end,
        T.any(
          SecretScanning::Features::Business::GenericSecrets,
          SecretScanning::Features::Org::GenericSecrets,
          SecretScanning::Features::User::GenericSecrets
        )
      )
    end

    sig { returns(T::Boolean) }
    def enabled_by_owning_business?
      return false if @generic_secrets.show_security_config_ux?
      case @generic_secrets
      when SecretScanning::Features::Org::GenericSecrets
        @generic_secrets.enabled_by_enterprise?
      else
        false
      end
    end

    delegate :feature_available?,
             :enabled?,
             :enable,
             :disable,
             :show_security_config_ux?,
      to: :@generic_secrets
  end
end
