# typed: true
# frozen_string_literal: true

module ProgrammaticAccess
  module ExpirationLimit
    def self.pat_lifetime_in_days_from(issued_at:, created_at:, expires_at:)
      return :unlimited if expires_at.nil?

      # We backfilled the last_issued_at column for OauthAccess at Dotcom and Proxima. GHES we could backfill it
      # but there are some cases that their Audit log retention policy is lower than the time we need to backfill. For
      # this reason we are going to use the created_at column as a fallback.
      # We should delete this after March 2026.
      issue_date = issued_at || T.must(created_at)

      expiry_timeframe_seconds = T.must(expires_at) - issue_date

      # In days
      ((expiry_timeframe_seconds) / (24 * 60 * 60)).round
    end

    # The lifetime of the PAT in days.
    #
    # Returns an Integer with the number of days the PAT is valid for or
    # :unlimited if the PAT does not expire.
    def pat_lifetime_in_days
      T.bind(self, T.any(OauthAccess, UserProgrammaticAccess))

      return @pat_lifetime_in_days if defined?(@pat_lifetime_in_days)
      ProgrammaticAccess::ExpirationLimit.pat_lifetime_in_days_from(issued_at: issued_at, created_at: created_at,
        expires_at: expires_at)
    end

    sig do
      params(
        target: T.untyped,
        access: T.any(OauthAccessTokens::IOauthAccess, OauthAccess, UserProgrammaticAccess),
        pat_lifetime_in_days: T.any(Symbol, Integer),
        pat_type: ProgrammaticAccessTokenType
      ).returns(T.nilable(T::Boolean))
    end
    def self.pat_adheres_by_targets_expiration_limit?(target, access:, pat_lifetime_in_days:, pat_type:)
      limit_enforcer = ProgrammaticAccessTokenLifetimeConfiguration.limit_enforcer_for(target)

      return nil unless limit_enforcer
      lifetime_configuration = ProgrammaticAccessTokenLifetimeConfiguration.new(limit_enforcer, pat_type)
      # GHES admins can exempt classic PATs without an issue date
      if !access.is_a?(UserProgrammaticAccess) && access.issued_at.nil? && lifetime_configuration.issued_at_exemption_enabled?
        return true
      end

      # The target's expiration limit policy.
      expiration_limit = lifetime_configuration.expiration_limit

      if expiration_limit.nil? # No limit set.
        return true
      end
      if pat_lifetime_in_days == :unlimited # PAT has no expiration
        return false
      end

      !pat_lifetime_in_days.is_a?(Symbol) && expiration_limit >= pat_lifetime_in_days
    end

    # Public: Does the PAT adhere to the expiration limit set by the target?
    #
    # Returns a Boolean or nil, where nil implies no limit enforcer is available.
    def pat_adheres_by_targets_expiration_limit?(target)
      T.bind(self, T.any(OauthAccess, UserProgrammaticAccess))
      ProgrammaticAccess::ExpirationLimit.pat_adheres_by_targets_expiration_limit?(target, access: self,
        pat_lifetime_in_days: pat_lifetime_in_days, pat_type: pat_type)
    end
  end
end
