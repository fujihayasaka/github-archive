# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: strict
# frozen_string_literal: true


# This job scans for EMU enterprises that have proxy security header enabled and
# sends a slack message if it is about to exceed the 500 count limit.
class MonitorEnterpriseAccessVerificationUsageJob < ApplicationJob
  queue_as :monitor_enterprise_access_verification_usage
  schedule interval: 12.hours
  retry_on_dirty_exit
  exempt_from_tenant_context_requirement

  sig { void }
  def perform
    return if GitHub.enterprise?
    return if GitHub.multi_tenant_enterprise?

    GitHub.logger.info("info.message" => "Starting monitor_enterprise_access_verification_usage job")

    count_enterprise_access_verification_usage

    GitHub.logger.info("info.message" => "Finished monitor_enterprise_access_verification_usage job")
  end

  private

  sig { void }
  def count_enterprise_access_verification_usage
    count = count_emu_businesses_with_proxy_header
    GitHub.logger.info("info.message" => "Total enterprise access verification usage", "info.count" => count)

    # Send Slack alerts based on thresholds
    force_slack_message = FeatureFlag.vexi.enabled?(:monitor_enterprise_access_verification_usage_force_slack, default: false) # for testing purposes
    if count >= 475 || force_slack_message
      send_slack_message(count: count, forced: force_slack_message)
    end
  end

  sig { returns(Integer) }
  def count_emu_businesses_with_proxy_header
    # Count EMU businesses (not staff-owned) with proxy security header enabled
    Business
      .where(business_type: "enterprise_managed")
      .not_staff_owned
      .to_a
      .count { |b| b.proxy_security_header_enabled? }
  end

  sig { params(count: Integer, forced: T::Boolean).void }
  def send_slack_message(count:, forced: false)
    begin
      message = "Total enterprise access verification customers: #{count}"

      prefix = if forced
        ":information_source: @inpreman @n-usha"
      elsif count >= 490 && count < 500
        ":warning: *Warning* :warning: @inpreman @n-usha"
      elsif count >= 500
        ":red_circle: *Critical* :red_circle: @inpreman @n-usha"
      end

      full_message = prefix ? "#{prefix}: #{message}" : message

      GitHub::Chatterbox.client.say!("#external-identities-ops", full_message)
    rescue => e
      GitHub.logger.error("MonitorEnterpriseAccessVerificationUsageJob failed to send slack message",
        "error.message" => "Failed to send Slack message",
        "error.details" => e.message
      )
    end
  end
end
