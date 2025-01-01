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
      policy_debug_logging("Checking limit enforcer for target", "pat_adheres_by_targets_expiration_limit?", { target: target, limit_enforcer: limit_enforcer })

      return nil unless limit_enforcer
      lifetime_configuration = ProgrammaticAccessTokenLifetimeConfiguration.new(limit_enforcer, pat_type)
      # GHES admins can exempt classic PATs without an issue date
      if is_a?(OauthAccess) && issued_at.nil? && lifetime_configuration.issued_at_exemption_enabled?
        policy_debug_logging("Returning true due to classic PAT exemption", "pat_adheres_by_targets_expiration_limit?", { target: target, lifetime_configuration: lifetime_configuration, result: true })
        return true
      end

      # The target's expiration limit policy.
      expiration_limit = lifetime_configuration.expiration_limit

      if expiration_limit.nil? # No limit set.
        policy_debug_logging("Returning true because no expiration limit is set", "pat_adheres_by_targets_expiration_limit?", { target: target, expiration_limit: expiration_limit, result: true })
        return true
      end
      if pat_lifetime_in_days == :unlimited # PAT has no expiration
        policy_debug_logging("Returning false because PAT has no expiration", "pat_adheres_by_targets_expiration_limit?", { target: target, pat_lifetime_in_days: pat_lifetime_in_days, result: false })
        return false
      end

      result = expiration_limit >= pat_lifetime_in_days
      policy_debug_logging("Returning based on comparison between expiration limit and PAT lifetime", "pat_adheres_by_targets_expiration_limit?", { target: target, expiration_limit: expiration_limit, pat_lifetime_in_days: pat_lifetime_in_days, result: result })
      result
    end

    def policy_debug_logging(msg, function, options = {})
      return unless FeatureFlag.vexi.enabled?(:evaluate_pat_filter_debug_logging, default: false)
      GitHub.logger.info(
        msg,
        {
          "code.function": function,
          "gh.request_id": GitHub.context[:request_id],
           **options
        }
      )
    end
  end
end
