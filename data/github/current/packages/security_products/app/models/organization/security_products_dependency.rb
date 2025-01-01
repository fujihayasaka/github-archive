# typed: true
# frozen_string_literal: true

module Organization::SecurityProductsDependency
  extend T::Helpers

  requires_ancestor { Organization }

  # Enables / disables security products for an organization based on automatic opt-in configuration
  # This method is called when an organization is created and applies
  # default settings for security products defined at the business level
  def setup_security_products_on_creation(user)
    business = self.associated_business_on_creation

    if business && business.security_alerts_enabled_for_new_repos?
      self.enable_security_alerts_for_new_repos(actor: user)
    end

    if business &&
      business.advanced_security_purchased?
      token_scanning = SecretScanning::Features::Business::TokenScanning.new(business)

      if business.advanced_security_enabled_on_new_repos?
        self.enable_advanced_security_on_new_repos(actor: user)
      end

      if token_scanning.feature_available?
        if SecretScanning::Features::Business::TokenScanning.new(business).secret_scanning_enabled_for_new_repos?
          SecretScanning::Features::Org::TokenScanning.new(self).enable_secret_scanning_for_new_repos(actor: user)
        end

        business_push_protection_features = SecretScanning::Features::Business::PushProtection.new(business)
        org_push_protection_features = SecretScanning::Features::Org::PushProtection.new(self)

        if business_push_protection_features.enabled_for_new_repos?
          org_push_protection_features.enable_for_new_repos(actor: user)
        end

        if business_push_protection_features.custom_message_active?
          org_push_protection_features.enable_custom_message(actor: user)
          business_custom_message = business.get_push_protection_custom_message
          self.set_push_protection_custom_message(business_custom_message, user)
        end
      end
    end
  end

  # Helper to check if any BlockedSettings are active for this organization
  #   _or_ if we're actively applying configurations.
  #
  sig { returns(T::Boolean) }
  def security_configurations_applying_or_blocked?
    jobs_in_progress? || security_configurations_blocked? || sibling_orgs_applying_security_configurations?
  end

  sig { returns(T::Boolean) }
  def jobs_in_progress?
    SecurityProductsEnablement::JobProgressTracker.new(T.must(id)).in_progress?
  end

  sig { returns(T::Boolean) }
  def security_configurations_blocked?
    BlockedSettings.new(T.cast(self, Organization)).any?
  end

  def sibling_orgs_applying_security_configurations?
    business = self.business
    return false unless business && SecurityProductsEnablement.enterprise_configs_enabled?(business)

    SecurityProductsEnablement::JobProgressTracker.business_jobs_running?(T.must(business.id))
  end
end
