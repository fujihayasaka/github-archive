# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class UserContributionCacheRefreshJob < ApplicationJob
  queue_as :user_contribution_cache_refresh_job

  MAX_CONCURRENT_JOBS = 10
  RESTRAINT_LOCK_TTL = 5.minutes
  LOCK_KEY = "user-contribution-cache-refresh-job:"

  MAX_RETRY_ATTEMPTS = 3
  RETRY_DELAY = 5.minutes

  retry_on_dirty_exit
  retry_on GitHub::Restraint::UnableToLock, wait: RETRY_DELAY, attempts: MAX_RETRY_ATTEMPTS do |_job, _error|
    GitHub.dogstats.increment(
      "external_identities.user_contribution_cache_refresh_job",
      tags: ["error:unable_to_lock"]
    )
  end

  resolve_tenant_context do |user_id|
    user = User.find_by(id: user_id)
    user&.enterprise_managed_business
  end

  # Public: Refresh this user's cached contributions. This is useful for
  #         matching commits to a new email address the user just added
  #         to their profile.
  #
  # user - The user we're refreshing contributions for
  #
  # Returns nothing
  def perform(user_id, options = {})
    unless user = User.find_by(id: user_id)
      GitHub.dogstats.increment("external_identities.user_contribution_cache_refresh_job.user_not_found")
      GitHub.logger.error({ "exception.message" => "User not found", "gh.user.id" => user_id })
      return
    end

    unless user.is_enterprise_managed?
      GitHub.dogstats.increment("external_identities.user_contribution_cache_refresh_job.not_emu")
      GitHub.logger.error({ "exception.message" => "User is not an EMU", "gh.user.id" => user.id })
      return
    end

    unless user.enterprise_managed_business.present?
      GitHub.dogstats.increment("external_identities.user_contribution_cache_refresh_job.business_not_found")
      GitHub.logger.error({ "exception.message" => "Business is not found", "gh.user.id" => user.id })
      return
    end

    Failbot.push(user_id: user.id)

    GitHub.logger.info(
      "info.message" => "Starting user_contribution_cache_refresh job",
      "gh.business.id" => user.enterprise_managed_business.id,
      "gh.business.slug" => user.enterprise_managed_business.slug,
    )

    lock!(user.id) do
      with_write do
        if options[:clear_contributions]
          clear_contributions(user)
        elsif options[:rebuild_contributions]
          begin
            rebuild_contributions(user)
          rescue GitHub::Restraint::UnableToLock
            GitHub.dogstats.increment("external_identities.user_contribution_cache_refresh_job.rebuild_contributions_unable_to_lock")
            GitHub.logger.error({ "exception.message" => "Unable to lock rebuild contributions", "gh.business.id" => user.enterprise_managed_business.id })
          rescue Freno::Throttler::Error
            GitHub.dogstats.increment("external_identities.user_contribution_cache_refresh_job.rebuild_contributions_throttler_error")
            GitHub.logger.error({ "exception.message" => "Rebuild contributions throttler error", "gh.business.id" => user.enterprise_managed_business.id })
          end
        end
      end
    end
    user.enterprise_managed_business&.update_license_usage

    GitHub.logger.info(
      "info.message" => "Finished user_contribution_cache_refresh job",
      "gh.business.id" => user.enterprise_managed_business.id,
      "gh.business.slug" => user.enterprise_managed_business.slug,
    )
  end

  private

  def clear_contributions(user)
    CommitContribution.clear_user_contributions!(user)
  end

  def rebuild_contributions(user)
    unless user.feature_flag_enabled?(:skip_user_contribution_rebuild, default: false)
      user.rebuild_contributions(context: "user_contribution_cache_refresh_job")
    end
  end

  # Private: The restraint for locking and preventing simultaneous jobs
  # for the same user.
  #
  # Returns GitHub::Restraint
  def restraint
    @restraint ||= GitHub::Restraint.new
  end

  # Private: Use a GitHub::Restraint to prevent simultaneous updates
  def lock!(user_id)
    restraint_key = "#{LOCK_KEY}#{user_id}"
    restraint.lock!(restraint_key, MAX_CONCURRENT_JOBS, RESTRAINT_LOCK_TTL) do
      yield
    end
  end
end
