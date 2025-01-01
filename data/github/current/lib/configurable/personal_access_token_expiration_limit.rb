# typed: true
# frozen_string_literal: true

module Configurable
  # Tracks the maximum expiration limit (in days) entities have set for personal access tokens.
  # Sets separate limits for classic and fine-grained personal access tokens.
  # The business-level limit is inherited by organizations.
  # Organizations can set their own limit, but it cannot exceed the business limit.
  module PersonalAccessTokenExpirationLimit
    extend T::Helpers

    requires_ancestor { Configurable }
    requires_ancestor { Kernel }

    PAT_CLASSIC_KEY = "personal_access_token_classic_expiration_limit"
    FG_PAT_KEY = "fine_grained_personal_access_token_expiration_limit"

    ORG_EXCEEDS_BUSINESS_LIMIT_ERROR = "Organization expiration limit cannot exceed the limit of the enterprise it belongs to."
    INVALID_EXPIRATION_LIMIT_ERROR = "Expiration limit must be between 1 and 366 days"

    DEFAULT_FINE_GRAINED_PAT_EXPIRATION_LIMIT = 366

    class ConfigurationError < StandardError; end

    sig do
      params(actor: ::User, expiration: Integer)
        .void
        .checked(:always)
        .on_failure(:raise)
    end
    def set_personal_access_token_classic_expiration_limit(actor:, expiration:)
      set_personal_access_token_expiration_limit(actor: actor, expiration: expiration, key: PAT_CLASSIC_KEY)
    end

    sig do
      params(actor: ::User, expiration: Integer)
        .void
        .checked(:always)
        .on_failure(:raise)
    end
    def set_fine_grained_personal_access_token_expiration_limit(actor:, expiration:)
      set_personal_access_token_expiration_limit(actor: actor, expiration: expiration, key: FG_PAT_KEY)
    end

    sig { returns(T.nilable(T.any(Organization, Business))) }
    def personal_access_token_classic_expiration_limit_target
      personal_access_token_expiration_limit_target(PAT_CLASSIC_KEY)
    end

    sig { params(ignore_inheritance: T::Boolean).returns(T.nilable(Integer)) }
    def personal_access_token_classic_expiration_limit(ignore_inheritance: false)
      personal_access_token_expiration_limit(PAT_CLASSIC_KEY, ignore_inheritance: ignore_inheritance)
    end

    sig { returns(T.nilable(T.any(Organization, Business))) }
    def fine_grained_personal_access_token_expiration_limit_target
      personal_access_token_expiration_limit_target(FG_PAT_KEY)
    end

    sig { params(ignore_inheritance: T::Boolean).returns(T.nilable(Integer)) }
    def fine_grained_personal_access_token_expiration_limit(ignore_inheritance: false)
      personal_access_token_expiration_limit(FG_PAT_KEY, ignore_inheritance: ignore_inheritance)
    end

    sig { params(actor: ::User).void }
    def disable_fine_grained_personal_access_token_expiration_limit(actor:)
      disable_personal_access_token_expiration_limit(actor: actor, key: FG_PAT_KEY)
    end

    sig { params(actor: ::User).void }
    def disable_personal_access_token_classic_expiration_limit(actor:)
      disable_personal_access_token_expiration_limit(actor: actor, key: PAT_CLASSIC_KEY)
    end

    sig { params(key: String, ignore_inheritance: T::Boolean).returns(T.nilable(Integer)) }
    def personal_access_token_expiration_limit(key, ignore_inheritance: false)
      case self
      when ::Business
        config.int(key)
      when ::Organization
        # return the more restrictive limit of the org and the parent business,
        # unless we're ignoring values inherited from the parent business
        if ignore_inheritance
          config.inherited?(key) ? nil : config.int(key)
        else
          [parent_business_limit(key), config.int(key)].compact.min
        end
      end
    end

    sig { params(key: String).returns(T.nilable(T.any(Organization, Business))) }
    def personal_access_token_expiration_limit_target(key)
      case self
      when ::Business
        self
      when ::Organization
        personal_access_token_expiration_limit(key) == parent_business_limit(key) ? self.business : self
      end
    end

    sig { params(ignore_inheritance: T::Boolean).returns(T::Boolean) }
    def fine_grained_personal_access_token_expiration_limit_enabled?(ignore_inheritance: false)
      personal_access_token_expiration_limit(FG_PAT_KEY, ignore_inheritance: ignore_inheritance).present?
    end

    sig { params(ignore_inheritance: T::Boolean).returns(T::Boolean) }
    def personal_access_token_classic_expiration_limit_enabled?(ignore_inheritance: false)
      personal_access_token_expiration_limit(PAT_CLASSIC_KEY, ignore_inheritance: ignore_inheritance).present?
    end

    # Copies the origin's fine-grained and classic expiration limit if the target does not have a limit set.
    sig { params(origin: T.any(Organization, Business), actor: T.nilable(User)).void }
    def copy_personal_access_token_expiration_limits(origin, actor:)
      actor ||= User.ghost
      if !personal_access_token_classic_expiration_limit_enabled?(ignore_inheritance: true) && new_classic_limit = origin.personal_access_token_classic_expiration_limit
        set_personal_access_token_classic_expiration_limit(actor: actor, expiration: new_classic_limit)
      end

      if !fine_grained_personal_access_token_expiration_limit_enabled?(ignore_inheritance: true) && new_fg_limit = origin.fine_grained_personal_access_token_expiration_limit
        set_fine_grained_personal_access_token_expiration_limit(actor: actor, expiration: new_fg_limit)
      end
    end

    private

    sig { params(actor: ::User, expiration: Integer, key: String).void }
    def set_personal_access_token_expiration_limit(actor:, expiration:, key:)
      raise(ConfigurationError, ORG_EXCEEDS_BUSINESS_LIMIT_ERROR) if org_exceeds_business_limit?(expiration, key)
      raise(ConfigurationError, INVALID_EXPIRATION_LIMIT_ERROR) unless expiration.between?(1, 366)
      return unless config.set(key, expiration, actor)
      instrument_expiration_limit(actor, expiration, key)
    end

    sig { params(actor: ::User, key: String).void }
    def disable_personal_access_token_expiration_limit(actor:, key:)
      config.delete(key, actor)
      instrument_disable_expiration_limit(actor, key)
    end

    sig { params(actor: ::User, expiration: Integer, key: String).void }
    def instrument_expiration_limit(actor, expiration, key)
      payload = expiration_limit_instrumentation_payload(actor, expiration)

      GlobalInstrumenter.instrument(key, payload)
    end

    sig { params(actor: ::User, key: String).void }
    def instrument_disable_expiration_limit(actor, key)
      payload = { user: actor, business: self }
      name = "#{key}_disabled"

      GlobalInstrumenter.instrument(name, payload)
    end

    sig { params(actor: ::User, expiration: Integer).returns(T::Hash[Symbol, T.any(::Business, ::Organization)]) }
    def expiration_limit_instrumentation_payload(actor, expiration)
      payload = { user: actor, expiration: expiration }

      case self
      when ::Business
        payload[:business] = self
      when ::Organization
        payload[:org] = self
        payload[:business] = self.business if self.business
      end

      payload
    end

    sig { params(key: String).returns(T.nilable(Integer)) }
    def parent_business_limit(key)
      return unless self.is_a?(Organization)
      return unless business.present?

      T.must(business).personal_access_token_expiration_limit(key)
    end

    sig { params(expiration: Integer, key: String).returns(T::Boolean) }
    def org_exceeds_business_limit?(expiration, key)
      business_limit = parent_business_limit(key)
      return false unless business_limit.present?

      expiration > business_limit
    end
  end
end
