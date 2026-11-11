# typed: true
# frozen_string_literal: true

class SecurityProductsBulkDisablementJob < ApplicationJob
  queue_as :security_products_bulk_disablement
  retry_on_dirty_exit

  def perform(entity:, actor:, service:, enablement_action: "trial_reset")
    success = false
    started_at = GitHub::Dogstats.monotonic_time

    # Observability: track how many orgs the entity has when this async job runs.
    # If this is 0 for a Business entity, it means orgs were already removed
    # before the job executed (the race condition we're investigating).
    #
    # See: https://github.com/github/security-products-enablement/issues/2494
    begin
      if FeatureFlag.vexi.enabled?("free_org_ghas_leak_observability", default: false) && entity.is_a?(Business)
        org_count = entity.organizations_limit_counter
        has_dfd_trial = entity.dfd_trial?
        has_ghas_trial = entity.has_active_advanced_security_trial?
        business_trial_expired = entity.trial_expired?
        business_trial_cancelled = entity.trial_cancelled?

        GitHub.dogstats.increment(
          "free_org_ghas_leak_observability.bulk_disable",
          tags: [
            "service:#{service}",
            "enablement_action:#{enablement_action}",
            "has_dfd_trial:#{has_dfd_trial}",
            "has_ghas_trial:#{has_ghas_trial}",
            "business_trial_expired:#{business_trial_expired}",
            "business_trial_cancelled:#{business_trial_cancelled}",
          ]
        )
        GitHub.dogstats.distribution(
          "free_org_ghas_leak_observability.bulk_disable.org_count",
          org_count,
          tags: [
            "service:#{service}",
            "enablement_action:#{enablement_action}",
            "has_dfd_trial:#{has_dfd_trial}",
            "has_ghas_trial:#{has_ghas_trial}",
            "business_trial_expired:#{business_trial_expired}",
            "business_trial_cancelled:#{business_trial_cancelled}",
          ]
        )
        GitHub.logger.info(
          "free_org_ghas_leak_observability.bulk_disable",
          "gh.business.id": entity.id,
          "gh.business.slug": entity.slug,
          "gh.business.org_count": org_count,
          "gh.business.has_dfd_trial": has_dfd_trial,
          "gh.business.has_ghas_trial": has_ghas_trial,
          "gh.business.trial_expired": business_trial_expired,
          "gh.business.trial_cancelled": business_trial_cancelled,
          "gh.service": service.to_s,
          "gh.enablement_action": enablement_action.to_s,
        )
      end
    rescue => error
      Failbot.report(error, context: "free_org_ghas_leak_observability")
    end

    begin
      with_write do
        BulkDisableService.disable_service_on_private_repos(entity, actor, service, enablement_action: enablement_action)
      end
      success = true
    rescue StandardError => e
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
