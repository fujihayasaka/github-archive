# typed: true
# frozen_string_literal: true

module SecurityProductsEnablement
  # Job to clean up enterprise-level security configurations when an enterprise
  # downgrades to team org status. This prevents orphaned configurations that
  # reference non-existent enterprises.
  class CleanUpEnterpriseSecurityConfigurationsJob < ApplicationJob
    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    queue_as :clean_up_enterprise_security_configurations

    sig { params(business_id: Integer, actor: User).void }
    def perform(business_id:, actor:)
      Failbot.push("code.namespace": self.class.name, "code.function": __method__, "gh.business.id": business_id)

      business = Business.find_by(id: business_id)

      unless business
        GitHub.logger.warn(
          "Business not found for security configuration cleanup",
          "code.namespace" => self.class.name,
          "code.function" => __method__,
          "gh.business.id" => business_id
        )
        return
      end

      enterprise_configs = SecurityConfiguration.where(target: business)
      deleted_count = 0
      return if enterprise_configs.count.zero?

      enterprise_configs.find_each do |config|
        with_write do
          # destroys the config along with repository_security_configurations
          config.delete_configuration(actor)
          deleted_count += 1
        end

        GitHub.logger.info(
          "Deleted enterprise security configuration during downgrade",
          "gh.security_products_enablement.security_configuration_id": config.id,
          "gh.business.id": business_id,
          "gh.actor.id": actor.id
        )
      end

      # Track the actual number of deleted configs
      GitHub.dogstats.count("business.downgrade.security_configurations_deleted", deleted_count)
      GitHub.dogstats.distribution("business.downgrade.security_configurations_deleted.count", deleted_count)

      GitHub.logger.info(
        "Completed security configuration cleanup",
        "code.namespace" => self.class.name,
        "code.function" => __method__,
        "gh.business.id" => business_id,
        "gh.security_configuration.count" => deleted_count
      )
    end
  end
end
