# typed: true
# frozen_string_literal: true

# Methods for Advanced Security billing concerns.
# Available on Business, Organization, and User objects.
#
# Doesn't actually store the data but knows how to delegate to the right place
# including for orgs that are part of a business. See `advanced_security_billing_config.rb`
# or the GHES license for the source of the data.
module Configurable
  module AdvancedSecurityBilling
    extend T::Helpers

    requires_ancestor { Configurable }

    include GitHub::Memoizer
    include Kernel

    sig { returns(T::Boolean) }
    def advanced_security_products_bundled?
      if GitHub.enterprise?
        # On GHES, we are "bundled" if _neither_ of the split-SKU products are enabled
        return !(GitHub::Enterprise.license.code_security_enabled || GitHub::Enterprise.license.secret_protection_enabled)
      end

      billable_owner = advanced_security_billable_entity
      # We only really expect nil for users that do not belong to an enterprise. No good
      # options here
      return true if billable_owner.nil?

      enablement_type = billable_owner.config.get(Configurable::AdvancedSecurityBillingConfig::ADVANCED_SECURITY_KEY)
      # Default to true if not present
      # This situation shouldn't happen, but it does in tests...which are difficult to track down
      return true if enablement_type.nil?

      [
        Configurable::AdvancedSecurityBillingConfig::GHAS_VOLUME,
        Configurable::AdvancedSecurityBillingConfig::GHAS_METERED
      ].include?(enablement_type)
    end

    sig { returns(T::Boolean) }
    def advanced_security_products_metered?
      if GitHub.enterprise?
        # On GHES, it is possible for the _license_ to be metered but still have a _volume_ subscription for GHAS features
        return true if GitHub::Enterprise.license.code_security_enabled && GitHub::Enterprise.license.metered_code_security?
        return true if GitHub::Enterprise.license.secret_protection_enabled && GitHub::Enterprise.license.metered_secret_protection?
        return true if GitHub::Enterprise.license.advanced_security_enabled && GitHub::Enterprise.license.metered_advanced_security?
        return false
      end

      billable_owner = advanced_security_billable_entity
      return false if billable_owner.nil?
      billable_owner.advanced_security_metered_for_entity?
    end

    # Public: Checks if the user has purchased Advanced Security.
    #
    # On GHES, this can be found by looking at the license file.
    # On Cloud:
    # * return false for users; they can't purchase GHAS
    # * for a business-owned org, check if the business has purchased GHAS
    #   and return that, regardless of org-level config
    # * for an "independent" org or a business itself, check the entity-level config
    #
    # Returns Boolean
    def advanced_security_purchased?
      T.bind(self, T.any(User, Organization, Business))

      if GitHub.enterprise?
        return true if GitHub::Enterprise.license.advanced_security_enabled
        return true if GitHub::Enterprise.license.code_security_enabled
        return true if GitHub::Enterprise.license.secret_protection_enabled
        return false
      end
      return if is_a?(Bot) || is_a?(Mannequin)

      case self
      when Business
        advanced_security_purchased_for_entity?
      when Organization
        return business&.advanced_security_purchased_for_entity? if delegate_billing_to_business?
        advanced_security_purchased_for_entity?
      when User
        ghas_for_users = ::AdvancedSecurity::Features::User::AdvancedSecurity.new(self)
        ghas_for_users.feature_available?
      end
    end

    # Public: Checks if the user has purchased Code Security.
    # This method checks against the correct billable entity.
    # This method does not distinguish between metered/volume billing types.
    # This method only considers the unbundled/split offering of Code Security, not the bundled GHAS offering.
    sig { returns(T::Boolean) }
    def code_security_purchased?
      T.bind(self, T.any(User, Organization, Business))

      return GitHub::Enterprise.license.code_security_enabled if GitHub.enterprise?
      return false if is_a?(Bot) || is_a?(Mannequin)

      case self
      when Business
        return true if ::EnterpriseCloudOnboard::CodeSecurityTrial.new(billable_entity: self).enabled?
        code_security_sku_purchased_for_entity?
      when Organization
        return business&.code_security_sku_purchased_for_entity? || false if delegate_billing_to_business?
        code_security_sku_purchased_for_entity?
      when User
        # Users cannot currently purchase Code Security
        false
      end
    end

    # Public: Checks if the user has purchased Secret Protection.
    # This method checks against the correct billable entity.
    # This method does not distinguish between metered/volume billing types.
    # This method only considers the unbundled/split offering of Secret Protection, not the bundled GHAS offering.
    sig { returns(T::Boolean) }
    def secret_protection_purchased?
      T.bind(self, T.any(User, Organization, Business))

      return GitHub::Enterprise.license.secret_protection_enabled if GitHub.enterprise?

      return false if is_a?(Bot) || is_a?(Mannequin)

      case self
      when Organization
        T.cast(self.billable_owner, T.any(Organization, Business)).secret_protection_purchased_for_entity?
      when Business
        return true if ::EnterpriseCloudOnboard::SecretProtectionTrial.new(billable_entity: self).enabled?
        self.secret_protection_purchased_for_entity?
      when User
        business = ::AdvancedSecurity::Features::User::AdvancedSecurity.new(self).get_business
        return false if business.nil?

        business.secret_protection_purchased_for_entity?
      end
    end

    sig { params(sku: GitHub::Turboghas::SKU).returns(Integer) }
    def advanced_security_seats_used(sku: GitHub::Turboghas::SKU::Bundled)
      T.bind(self, T.any(User, Organization, Business))
      license = advanced_security_license_for_sku(sku:)
      return 0 unless license.purchased?
      license.entity_summary.active_committers
    end

    def advanced_security_business_user_accounts(sku:)
      return self.class.none unless is_a?(Business)

      scope = user_accounts.joins(:enterprise_installation_user_accounts)

      table = EnterpriseInstallationUserAccount.arel_table

      clause = case sku
      when GitHub::Turboghas::SKU::Bundled
        table[:using_code_security].eq(true).or(table[:using_secret_protection].eq(true)).expr
      when GitHub::Turboghas::SKU::CodeSecurity
        table[:using_code_security].eq(true)
      when GitHub::Turboghas::SKU::SecretSecurity
        table[:using_secret_protection].eq(true)
      end

      scope.where(table[:using_advanced_security].eq(true).or(clause))
    end

    def advanced_security_business_user_ids(sku:)
      advanced_security_business_user_accounts(sku:).where.not(user_id: nil).distinct.pluck(:user_id)
    end

    # Calculates how many extra GHAS seats would be used / contributors would be
    # billed for if GHAS were to be enabled on every repository in this user / org.
    #
    # Returns 0 if GHAS is not purchased.
    memoize def seat_usage_increase_if_advanced_security_enabled_for_all_repos
      T.bind(self, T.any(User, Organization, Business))
      return 0 unless self.advanced_security_purchased?

      GitHub.dogstats.distribution_time("advanced_security_contribution.dist.business_settings_page_enable_all") do
        AdvancedSecurityLicense.seat_usage_increase_if_advanced_security_enabled_for_all_repos(owner: self)
      end
    end

    # If GHAS were to be enabled on all repos, would the GHAS license then be exceeding its seat limit.
    # This includes if the limit is already exceeded.
    def enabling_advanced_security_for_all_repos_would_exceed_seat_allowance?
      T.bind(self, T.any(User, Organization, Business))
      return false unless advanced_security_purchased?
      return false if advanced_security_license.unlimited_seats?

      tags = if self.is_a?(Business)
        {
          "gh.business.id" => id,
          "gh.business.name" => slug
        }
      else
        {
          "gh.org.id" => id,
          "gh.org.login" => display_login
        }
      end

      if advanced_security_license.allowance_exceeded?
        GitHub.logger.info(
          "Enable all seat allowance already exceeded",
          "code.namespace" => self.class.name,
          "code.function" => __method__.to_s,
          **tags,
        )

        return true
      end

      would_exceed_seat_allowance = seat_usage_increase_if_advanced_security_enabled_for_all_repos > advanced_security_license.remaining_seats
      if would_exceed_seat_allowance
        GitHub.logger.info(
          "Enable all will exceed seat allowance",
          "code.namespace" => self.class.name,
          "code.function" => __method__.to_s,
          **tags,
        )
      end

      would_exceed_seat_allowance
    end

    # Public: Is the billable entity for GHAS
    def advanced_security_billable_entity?
      self == advanced_security_billable_entity
    end

    memoize def advanced_security_billable_entity
      T.bind(self, T.any(User, Business))
      AdvancedSecurityLicense.billable_entity(self)
    end

    sig { params(sku: GitHub::Turboghas::SKU).returns(AdvancedSecurityLicense) }
    def advanced_security_license_for_sku(sku:)
      T.bind(self, T.any(User, Business))
      case sku
      when GitHub::Turboghas::SKU::Bundled
        advanced_security_license
      when GitHub::Turboghas::SKU::CodeSecurity
        code_security
      when GitHub::Turboghas::SKU::SecretSecurity
        secret_protection
      end
    end

    # Public: Returns the license object for the current entity.
    sig { returns(AdvancedSecurityLicense) }
    memoize def advanced_security_license
      T.bind(self, T.any(User, Business))
      AdvancedSecurityLicense.new(self, sku: GitHub::Turboghas::SKU::Bundled)
    end

    sig { returns(AdvancedSecurityLicense) }
    memoize def secret_protection
      T.bind(self, T.any(User, Organization, Business))
      AdvancedSecurityLicense.new(self, sku: GitHub::Turboghas::SKU::SecretSecurity)
    end

    sig { returns(AdvancedSecurityLicense) }
    memoize def code_security
      T.bind(self, T.any(User, Organization, Business))
      AdvancedSecurityLicense.new(self, sku: GitHub::Turboghas::SKU::CodeSecurity)
    end
  end
end
