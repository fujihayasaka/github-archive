# typed: true
# frozen_string_literal: true

module ProgrammaticAccess
  module ExpirationLimit
    # The lifetime of the PAT in days.
    #
    # Returns an Integer with the number of days the PAT is valid for or
    # :unlimited if the PAT does not expire.
    def pat_lifetime_in_days
      T.bind(self, T.any(OauthAccess, UserProgrammaticAccess))

      return @pat_lifetime_in_days if defined?(@pat_lifetime_in_days)
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

    # Does the PAT adhere to the expiration limit set by the target?
    #
    # Returns a Boolean.
    def pat_adheres_by_targets_expiration_limit?(target)
      T.bind(self, T.any(OauthAccess, UserProgrammaticAccess))
      limit_enforcer = ProgrammaticAccessTokenLifetimeConfiguration.limit_enforcer_for(target)
      return nil unless limit_enforcer
      lifetime_configuration = ProgrammaticAccessTokenLifetimeConfiguration.new(limit_enforcer, pat_type)

      # GHES admins can exempt classic PATs without an issue date
      if is_a?(OauthAccess) && issued_at.nil? && lifetime_configuration.issued_at_exemption_enabled?
        return true
      end

      # The target's expiration limit policy.
      expiration_limit = lifetime_configuration.expiration_limit

      return true if expiration_limit.nil? # No limit set.
      return false if pat_lifetime_in_days == :unlimited # PAT has no expiration

      expiration_limit >= pat_lifetime_in_days
    end
  end
end
