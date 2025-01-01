
# typed: strict
# frozen_string_literal: true

module Configurable
  # Tracks which entities have enabled an exemption for the personal access token expiration limit
  # This exemption applies to Enterprise Admins
  module PersonalAccessTokenExpirationLimitExemptionEnabled
    extend T::Helpers

    requires_ancestor { Configurable }
    requires_ancestor { Kernel }

    PAT_CLASSIC_KEY = T.let("personal_access_token_classic_expiration_limit_exemption", String)
    FG_PAT_KEY = T.let("fine_grained_personal_access_token_expiration_limit_exemption", String)
    MISSING_ISSUED_AT_EXEMPTION_KEY = T.let("personal_access_token_classic_creation_date_missing_exemption", String)

    class ConfigurationError < StandardError; end

    sig { params(actor: ::User).void }
    def enable_personal_access_token_classic_expiration_limit_exemption(actor:)
      enable_personal_access_token_expiration_limit_exemption(actor: actor, key: PAT_CLASSIC_KEY)
    end

    sig { params(actor: ::User).void }
    def disable_personal_access_token_classic_expiration_limit_exemption(actor:)
      disable_personal_access_token_expiration_limit_exemption(actor: actor, key: PAT_CLASSIC_KEY)
    end

    sig { params(actor: ::User).void }
    def enable_fine_grained_personal_access_token_expiration_limit_exemption(actor:)
      enable_personal_access_token_expiration_limit_exemption(actor: actor, key: FG_PAT_KEY)
    end

    sig { params(actor: ::User).void }
    def disable_fine_grained_personal_access_token_expiration_limit_exemption(actor:)
      disable_personal_access_token_expiration_limit_exemption(actor: actor, key: FG_PAT_KEY)
    end

    sig { returns(T::Boolean) }
    def personal_access_token_classic_expiration_limit_exemption_enabled?
      config.enabled?(PAT_CLASSIC_KEY)
    end

    sig { returns(T::Boolean) }
    def fine_grained_personal_access_token_expiration_limit_exemption_enabled?
      config.enabled?(FG_PAT_KEY)
    end

    sig { params(actor: User).returns(T::Boolean) }
    def personal_access_token_classic_expiration_limit_exempted_for?(actor)
      T.bind(self, Business)

      personal_access_token_classic_expiration_limit_exemption_enabled? && (owner?(actor) || billing_manager?(actor))
    end

    sig { params(actor: User).returns(T::Boolean) }
    def fine_grained_personal_access_token_expiration_limit_exempted_for?(actor)
      T.bind(self, Business)

      fine_grained_personal_access_token_expiration_limit_exemption_enabled? && (owner?(actor) || billing_manager?(actor))
    end

    # This is a special case for the missing issued at exemption on GHES only (see https://github.com/github/ecosystem-apps/issues/6315)
    sig { returns(T::Boolean) }
    def personal_access_token_classic_missing_issued_at_exemption_enabled?
      T.bind(self, Business)

      return false unless GitHub.enterprise?
      config.enabled?(MISSING_ISSUED_AT_EXEMPTION_KEY)
    end

    sig { params(actor: ::User).void }
    def enable_personal_access_token_classic_missing_issued_at_exemption(actor:)
      return unless GitHub.enterprise?
      return unless config.enable!(MISSING_ISSUED_AT_EXEMPTION_KEY, actor)
      instrument_expiration_limit_exemption(actor, "#{MISSING_ISSUED_AT_EXEMPTION_KEY}_enabled")
    end

    sig { params(actor: ::User).void }
    def disable_personal_access_token_classic_missing_issued_at_missing_exemption(actor:)
      return unless GitHub.enterprise?
      return unless config.delete(MISSING_ISSUED_AT_EXEMPTION_KEY, actor)
      instrument_expiration_limit_exemption(actor, "#{MISSING_ISSUED_AT_EXEMPTION_KEY}_disabled")
    end

    private

    sig { params(actor: ::User, key: String).void }
    def enable_personal_access_token_expiration_limit_exemption(actor:, key:)
      return unless config.enable!(key, actor)
      instrument_expiration_limit_exemption(actor, "#{key}_enabled")
    end

    sig { params(actor: ::User, key: String).void }
    def disable_personal_access_token_expiration_limit_exemption(actor:, key:)
      return unless config.delete(key, actor)
      instrument_expiration_limit_exemption(actor, "#{key}_disabled")
    end

    sig { params(actor: ::User, key: String).void }
    def instrument_expiration_limit_exemption(actor, key)
      payload = { user: actor, business: self }
      GlobalInstrumenter.instrument(key, payload)
    end
  end
end
