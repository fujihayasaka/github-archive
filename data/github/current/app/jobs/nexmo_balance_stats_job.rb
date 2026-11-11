# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class NexmoBalanceStatsJob < ApplicationJob
  queue_as :nexmo_balance_stats
  retry_on_dirty_exit

  schedule interval: 10.minutes, condition: -> { GitHub.two_factor_sms_enabled? }

  # this job does not run in Proxima since SMS 2FA isn't supported
  exempt_from_tenant_context_requirement

  def perform
    return unless GitHub::Messaging.providers_for_env.map(&:provider_name).include?(:vonage)

    provider = GitHub::Messaging::Vonage.new
    balance = provider.account_balance
    GitHub.dogstats.gauge("two_factor.nexmo_balance", balance)
  end
end
