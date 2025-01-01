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

      issue_date = if GitHub.flipper[:use_issued_at_to_calculate_pat_lifetime].enabled?
        issued_at || T.must(created_at)
      else
        T.must(created_at)
      end
      expiry_timeframe_seconds = T.must(expires_at) - issue_date

      # In days
      ((expiry_timeframe_seconds) / (24 * 60 * 60)).round
    end

    # Does the PAT adhere to the expiration limit set by the target?
    #
    # Returns a Boolean.
    def pat_adheres_by_targets_expiration_limit?(target)
      T.bind(self, T.any(OauthAccess, UserProgrammaticAccess))
      lifetime_configuration = ProgrammaticAccessTokenLifetimeConfiguration.new(target, pat_type)

      # GHES admins can exempt classic PATs without an issue date
      if is_a?(OauthAccess) && issued_at.nil? && lifetime_configuration.issued_at_exemption_enabled? && target.feature_enabled?(:pat_issued_at_exemption)
        return true
      end

      # The target's expiration limit policy.
      expiration_limit = if target.feature_enabled?(:pat_issued_at_exemption)
        lifetime_configuration.expiration_limit
      else
        ProgrammaticAccessTokenLifetimeConfiguration.expiration_limit_for(target, pat_type)
      end

      return true if expiration_limit.nil? # No limit set.
      return false if pat_lifetime_in_days == :unlimited # PAT has no expiration

      expiration_limit >= pat_lifetime_in_days
    end
  end
end
