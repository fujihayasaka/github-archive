# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# FindAccountsEligibleForDisablePublicIpJob is tasked with finding accounts (Organization or Business/Enterprise)
# whose plan has changed to a non enterprise plan in the last 24 hours. We then schedule a seperate job to check whether
# these entities are using Public IP ranges for Larger Runner Pools, in order to disable them.

# An Organization can have their own Larger Runner Pools, or inherit from the Enterprise. In this scenario,
# we only wish to disable the non-inherited Larger Runner Pools.
# A downgraded Organization is marked by an entry in the transactions table with an action of 'downgraded' and a current
# non business_plus plan. We schedule the downgrade against the Organization using a grace period of N days determined by the
# TrustTier of the Organization. See

# A downgraded Enterprise is marked by a non null 'downgraded_at' field in the Business table, with the time of the
# downgrade.
# For an Enterprise which is downgraded, we must consider two scenarios:
# 1. The member Organizations using their own Larger Runner Pools
# 2. The Enterprise level Larger Runner Pools

module Actions::LargerRunners
  class FindAccountsEligibleForDisablePublicIpJob < ApplicationJob

    queue_as :larger_runner_schedule_account_disable_public_ip

    schedule interval: 1.day, condition: -> { GitHub.actions_larger_runners_enabled? }

    # The database is configured to store records in `localtime`,
    # so we configure ActiveRecord to auto convert to UTC, so we can search based on UTC.
    # See config/application.rb#L213-217
    @yesterday_end = DateTime.yesterday.at_end_of_day.utc
    @yesterday_start = DateTime.yesterday.at_beginning_of_day.utc

    retry_on_dirty_exit

    retry_on(ActiveRecord::ConnectionFailed, wait: :polynomially_longer, attempts: 3) do |_job, error|
      GitHub.dogstats.increment(
        "larger_runner_schedule_account_disable_public_ip.job_error",
        tags: ["search_date_range:#{@yesterday_start} / #{@yesterday_end}"]
      )
      Failbot.report(error)
    end

    def downgraded_accounts

      downgraded_accounts = Hash.new

      ActiveRecord::Base.connected_to(role: :reading) do
        Business
        .where.not(downgraded_at: nil)
        .where(downgraded_at: (@yesterday_start..@yesterday_end))
        .find_each do |business|
          if business.is_larger_runners_onboarded?
            downgraded_accounts[business] = business.downgraded_at
          end
        end
      end

      ActiveRecord::Base.connected_to(role: :reading) do
        Transaction
        .where(timestamp: (@yesterday_start..@yesterday_end), action: "downgraded")
        .where.not(current_plan: GitHub::Plan::BUSINESS_PLUS)
        .find_each do |transaction|
          org = Organization.find_by(id: transaction.user_id)
          if org.present? && org.is_larger_runners_onboarded?
            downgraded_accounts[org] = transaction.timestamp
          end
        end
      end
      downgraded_accounts
    end

    def perform
      return unless GitHub.flipper[:for_downgraded_accounts_disable_public_ip].enabled?

      execution_time = Time.now.utc

      downgraded_accounts.each do |downgraded_account, downgraded_at|
        grace_period_days = Actions::LargerRunner::PublicIPSettings.graceful_days_for(downgraded_account)
        # If grace period is 1 day. Most likely the job
        # has picked up this transaction around about the time we need to downgrade.
        if grace_period_days == 1
          delay_in_hours = untrusted_account_job_wait_time(execution_time, downgraded_at)
          schedule_for = execution_time.advance(hours: delay_in_hours)
          DisableAccountPublicIpJob.set(wait_until: schedule_for).perform_later(downgraded_account)
        else
          schedule_for = downgraded_at.advance(days: grace_period_days)
          DisableAccountPublicIpJob.set(wait_until: schedule_for).perform_later(downgraded_account)
        end
        GitHub.dogstats.increment(
          "actions.larger_runners.disable_public_ip.scheduled.count",
          tags: ["account_type:#{downgraded_account.class.name}"],
        )
      end
    end

    def untrusted_account_job_wait_time(execution_time, downgraded_at)
      # If it has been 24 hours or more since the downgrade, then delay is 0, we do not wait.
      # If it has been less than 24 hours, give up to 24 hours.
      elapsed_time_since_downgrade = ((execution_time - downgraded_at) / 1.hour).round
      [24 - elapsed_time_since_downgrade, 0].max
    end
  end
end
