# typed: true
# frozen_string_literal: true

class SecurityProductsBulkDisablementJob < ApplicationJob
  queue_as :security_products_bulk_disablement
  retry_on_dirty_exit

  def perform(entity:, actor:, service:, enablement_action: "trial_reset")
    success = false
    started_at = GitHub::Dogstats.monotonic_time

    begin
      with_write do
        BulkDisableService.disable_service_on_private_repos(entity, actor, service, enablement_action: enablement_action)
      end
      success = true
    rescue StandardError => e # rubocop:todo Lint/RescueException
      Failbot.report(e, {
        "code.namespace": self.class.name,
        "code.function": __method__,
      })
    ensure
      GitHub.dogstats.increment("secret_scanning.security_product_bulk_disablement.complete", tags: ["success:#{success}"])
      GitHub.dogstats.distribution("secret_scanning.security_product_bulk_disablement.duration", GitHub::Dogstats.duration(started_at))
    end
  end
end
