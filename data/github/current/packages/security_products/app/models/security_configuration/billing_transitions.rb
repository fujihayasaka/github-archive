# typed: strict
# frozen_string_literal: true

# Encapsulates billing-state transitions (bundled ↔ unbundled GHAS) and the
# batch transition logic triggered by billing changes.
module SecurityConfiguration::BillingTransitions
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { SecurityConfiguration }

  module ClassMethods
    sig { params(billable_entity: Billing::Types::OrgOrBusiness, bundled_ghas: T::Boolean).void }
    def advanced_security_billing_toggled(billable_entity, bundled_ghas)
      T.bind(self, T.class_of(SecurityConfiguration))
      existing_configs = T.let([], T::Array[SecurityConfiguration])

      logging_tags = {
        "code.namespace": self.name,
        "code.function": Kernel.__method__,
        "gh.security_products_enablement.current_billing_state": bundled_ghas
      }

      if billable_entity.is_a?(Organization)
        logging_tags["gh.organization.id"] = billable_entity.id
        existing_configs = SecurityConfiguration.where(target: billable_entity).to_a
      elsif billable_entity.is_a?(Business)
        logging_tags["gh.business.id"] = billable_entity.id
        existing_configs = SecurityConfiguration.where(target: billable_entity).to_a
        # Organization inherits from User, so org-level configs use target_type "User".
        existing_configs.concat(SecurityConfiguration.where(target_type: "User", target_id: billable_entity.organization_ids).to_a)
      end

      return if existing_configs.empty?

      logging_tags["gh.security_products_enablement.security_configuration_ids"] = existing_configs.map(&:id).join(",")

      GitHub.logger.with_named_tags(logging_tags) do
        GitHub.logger.info("Updating security configurations to match billing state")
        existing_configs.each do |config|
          transition_config(config, bundled_ghas)
        end
        GitHub.logger.info("Finished updating security configurations to match billing state")
      end
    end

    private

    sig { params(configuration: SecurityConfiguration, bundled_ghas: T::Boolean).void }
    def transition_config(configuration, bundled_ghas)
      if bundled_ghas && configuration.instance_of?(UnbundledSecurityConfiguration)
        configuration.bundle!
      elsif !bundled_ghas && configuration.instance_of?(SecurityConfiguration)
        configuration.unbundle!
      end
    rescue ActiveRecord::RecordInvalid => e
      logging_tags = {
        "code.function": Kernel.__method__,
        "gh.security_products_enablement.security_configuration_id": configuration.id,
        "exception": e,
      }
      GitHub.logger.info("Failed to transition security configuration", logging_tags)
      Failbot.report(e)
    end
  end

  sig { returns(UnbundledSecurityConfiguration) }
  def unbundle!
    raise ArgumentError, "Cannot unbundle global configurations" if global?
    raise ArgumentError, "Can only unbundle a SecurityConfiguration" unless instance_of?(SecurityConfiguration)

    unbundled = T.cast(becomes!(UnbundledSecurityConfiguration), UnbundledSecurityConfiguration)

    if enable_ghas
      unbundled.enable_ghas = false
      # Only enable CS / SP when it is actually used. Otherwise it should be `not_set`.
      unbundled.code_security_sku_enabled = SecurityConfiguration::CODE_SECURITY_FEATURES.any? { |feature| send("#{feature}_enabled?") } || nil
      unbundled.secret_protection_sku_enabled = SecurityConfiguration::SECRET_PROTECTION_FEATURES.any? { |feature| send("#{feature}_enabled?") } || nil
    end

    unbundled.save!

    unbundled
  end
end
