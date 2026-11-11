# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: strict
# frozen_string_literal: true

# DisableAccountPublicIpJob disables the Public IP's for Larger Runners for accounts
# downgraded to a non enterprise plan. See https://github.com/github/github/pull/231714 for more details

module Actions::LargerRunners
  class DisableAccountPublicIpJob < ApplicationJob
    include Actions::LargerRunnersControllerHelper

    queue_as :background_larger_runner_disable_account_public_ip

    retry_on_recoverable_exceptions
    retry_on_dirty_exit

    # Prevent duplicate scheduling of this job for a given account. Set timeout to exceed
    # The maxium number of days ahead we schedule this job for (7 days).
    # See Actions::LargerRunners::FindAccountsEligibleForDisablePublicIpJob#L81-88
    locked_by key: DEFAULT_LOCK_PROC, timeout: 8.days

    discard_on ActiveJob::DeserializationError, ActiveRecord::RecordNotFound do |_, error|
      Failbot.report(error)
    end

    class DisableAccountPublicIpJobError < RuntimeError
      sig { returns(T.nilable(Integer)) }
      attr_reader :account_id

      sig { returns(T.nilable(String)) }
      attr_reader :account_type

      sig { returns(T.nilable(T::Array[Integer])) }
      attr_reader :failed_pool_ids

      sig do
        params(
          message: String,
          account_id: T.nilable(Integer),
          account_type: T.nilable(String),
          failed_pool_ids: T.nilable(T::Array[Integer])
        ).void
      end
      def initialize(message, account_id: nil, account_type: nil, failed_pool_ids: nil)
        super(message)
        @account_id = account_id
        @account_type = account_type
        @failed_pool_ids = failed_pool_ids
      end
    end

    retry_on DisableAccountPublicIpJobError, wait: 2.seconds, attempts: 2 do |error|
      Failbot.report(
        error,
        account_id: error.account_id,
        account_type: error.account_type,
        failed_pool_ids: error.failed_pool_ids,
      )
      GitHub.dogstats.increment("actions.larger_runners.disable_public_ip", tags: ["state:failure"])
    end

    sig { params(account: T.any(Organization, Business)).void }
    def perform(account)
      account = account.reload
      return unless account.is_larger_runners_onboarded?
      return if account.spammy?

      if account.is_a?(Organization)
        return if is_public_ip_allowed_for_entity?(account)

        disabled_pool_names, failed_pool_ids = disable_pools_for(account)

        send_org_email(account, disabled_pool_names)
        raise_error(account.id, failed_pool_ids) if failed_pool_ids.any?

      elsif account.is_a?(Business)
        return if is_public_ip_allowed_for_entity?(account)
        all_failed_pools = []
        # Disable Public IP for all Enterprise level Larger Runners
        disabled_ent_pool_names, failed_ent_pool_ids = disable_pools_for(account)
        all_failed_pools += failed_ent_pool_ids if failed_ent_pool_ids.any?
        successful_member_orgs = []

        account.organizations.each do |organization|
          # Disable Public IP for all Organization level Larger Runners
          successful_org_pools, failed_org_pool_ids = disable_pools_for(organization)
          successful_member_orgs.push(organization.name) if successful_org_pools.any?
          all_failed_pools += failed_org_pool_ids if failed_org_pool_ids.any?
        end

        send_enterprise_email(account, disabled_ent_pool_names, successful_member_orgs)
        raise_error(account.id, all_failed_pools) if all_failed_pools.any?
      end
    end

    sig { params(account_id: T.nilable(Integer), failed_pool_ids: T::Array[Integer]).void }
    def raise_error(account_id, failed_pool_ids)
      raise DisableAccountPublicIpJobError.new(
        "Failed to disable some public IP ranges for account",
        account_id: account_id,
        failed_pool_ids: failed_pool_ids,
      )
    end

    sig do
      params(
        account: T.any(Organization, Business)
      ).returns([T::Array[String], T::Array[Integer]])
    end
    def disable_pools_for(account)
      disable_success_timer = Timer.start
      pools = get_pools_with_public_ip_enabled(account)
      disabled_pool_names, failed_pool_ids = disable_ip_for_all_eligible_pools(account, pools)

      if disabled_pool_names.any?
        disable_success_timer.stop
        GitHub.dogstats.increment("actions.larger_runners.disable_public_ip", tags: ["state:success"])
        GitHub.dogstats.distribution("actions.larger_runners.disable_public_ip.duration_ms", disable_success_timer.elapsed_ms)
      end

      [disabled_pool_names, failed_pool_ids]
    end

    sig do
      params(
        account: T.any(Organization, Business),
        pools: T::Array[Actions::LargerRunner]
      ).returns([T::Array[String], T::Array[Integer]])
    end
    def disable_ip_for_all_eligible_pools(account, pools)
      failed_pool_ids = []
      disabled_pool_names = []

      pools.each do |pool|
        if disable_ip_for_runner_pool(account, pool).call_succeeded?
          disabled_pool_names << pool.name
        else
          failed_pool_ids << pool.id
        end
      end
      [disabled_pool_names, failed_pool_ids]
    end

    sig { params(account: T.any(Organization, Business)).returns(T::Array[Actions::LargerRunner]) }
    def get_pools_with_public_ip_enabled(account)
      pools = Actions::LargerRunner.larger_runners_for(
        entity: account,
        is_public_ip_enabled: true
      )
      .reject(&:inherited?) # Exclude pools shared within an Enterprise
    end

    sig do
      params(
        account: T.any(Organization, Business),
        runner: Actions::LargerRunner
      ).returns(T::untyped) # Response status
    end
    def disable_ip_for_runner_pool(account, runner)
      runner.is_public_ip_enabled = false
      runner.labels = [] # Indicates no update to labels
      update_larger_runners_for(account, larger_runner: runner, actor: nil)
    end

    sig do
      params(
        business: Business,
        enterprise_pools: T::Array[String],
        member_orgs: T::Array[Organization]
      ).void
    end
    def send_enterprise_email(business, enterprise_pools, member_orgs)
      if enterprise_pools.any? || member_orgs.any?
        LargerRunnersAccountIpDisableMailer
        .public_ip_change_for_enterprise(business, enterprise_pools, member_orgs).deliver_later
      end
    end

    sig do
      params(
        organization: Organization,
        org_pools: T::Array[String]
      ).void
    end
    def send_org_email(organization, org_pools)
      if org_pools.any?
        LargerRunnersAccountIpDisableMailer
        .public_ip_change_for_org(organization, org_pools).deliver_later
      end
    end
  end
end
