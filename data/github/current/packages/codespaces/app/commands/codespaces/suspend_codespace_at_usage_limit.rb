# typed: true
# frozen_string_literal: true

module Codespaces
  class SuspendCodespaceAtUsageLimit < Command
    include GitHub::Memoizer

    def initialize(codespace:)
      @codespace = codespace
      @usage_checker = Codespaces::AccessChecker.from_codespace(@codespace, fast_timeout: false)
    end

    def perform
      return if !codespace.suspendable?

      if usage_result.disallowed? && stop_notice
        cache_last_known_stop_notice

        CodespacesSuspendEnvironmentJob.perform_later(
          codespace: codespace,
          suspension_reason: CodespacesSuspendEnvironmentJob::USAGE_LIMITS_REACHED_REASON
        )
      end
    end

    private

    attr_reader :codespace, :usage_checker

    memoize def usage_result
      # While we have the codespace on hand, we don't want to pass the policy-relevant
      # arguments here as that would suspend based on policy violations, something we're not ready to do.
      usage_checker.run_billing_check
    end

    memoize def stop_notice
      if usage_result.disallowed_by_entitlements?
        LastKnownStopNoticeCache::ENTITLEMENTS_LIMIT_REACHED_FOR_USER
      elsif usage_result.disallowed_by_spending_limit?
        if codespace.billable_owner.user?
          LastKnownStopNoticeCache::SPENDING_LIMIT_REACHED_FOR_USER
        else
          LastKnownStopNoticeCache::SPENDING_LIMIT_REACHED_FOR_ORG
        end
      elsif usage_result.disallowed_by_billing?
        if codespace.billable_owner.user?
          LastKnownStopNoticeCache::GENERIC_BILLING_ERROR_FOR_USER
        else
          LastKnownStopNoticeCache::GENERIC_BILLING_ERROR_FOR_ORG
        end
      end
    end

    def cache_last_known_stop_notice
      LastKnownStopNoticeCache.mset(
        billable_owner_ids: [codespace.billable_owner.id],
        notice: stop_notice
      )
    end
  end
end
