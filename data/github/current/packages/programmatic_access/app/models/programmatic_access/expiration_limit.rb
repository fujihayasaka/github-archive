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

      expiry_timeframe_seconds = T.must(expires_at) - T.must(created_at)

      # In days
      ((expiry_timeframe_seconds) / (24 * 60 * 60)).round
    end

    # Does the PAT adhere to the expiration limit set by the target?
    #
    # Returns a Boolean.
    def pat_adheres_by_targets_expiration_limit?(target)
      T.bind(self, T.any(OauthAccess, UserProgrammaticAccess))

      # The target's expiration limit policy.
      expiration_limit = ProgrammaticAccessTokenLifetimeConfiguration.expiration_limit_for(target, pat_type)
      return true if expiration_limit.nil? # No limit set.
      return false if pat_lifetime_in_days == :unlimited # PAT has no expiration

      expiration_limit >= pat_lifetime_in_days
    end
  end
end
