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

      billable_owner.advanced_security_products_bundled_for_entity?
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

    # Gets the total number of active users for the high watermark sku
    sig { params(sku: GitHub::Turboghas::SKU).returns(Integer) }
    def advanced_security_billable_licenses(sku:)
      T.bind(self, T.any(Organization, Business))

      product = Licensing::Licensify::LicensifyProduct.from_turboghas_sku(sku)
      license_attributer = ::AdvancedSecurity::LicenseAttributer.new(self, product:)

      license_attributer.billable_cloud_user_count
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
      when Business, Organization
        return false if self.billable_owner.nil?
        billable_owner = T.cast(self.billable_owner, T.any(Organization, Business))
        billable_owner.advanced_security_purchased_for_entity? ||
        ::EnterpriseCloudOnboard::CodeSecurityTrial.new(billable_entity: billable_owner).enabled?
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

      entity = case self
      when Organization
        T.cast(self.billable_owner, T.any(Organization, Business))
      when Business
        self
      when User
        # users can't purchase Code Security
        nil
      end
      return false if entity.nil?

      return true if ::EnterpriseCloudOnboard::CodeSecurityTrial.new(billable_entity: entity).enabled?
      entity.code_security_purchased_for_entity?
    end

    # Public: Checks if the user has the unbundled SKU of Secret Protection available for purchase.
    # This does not actually check if GHSP was paid for with money, despite the method's name.
    # This method checks against the correct billable entity.
    # This method does not distinguish between metered/volume billing types.
    # This method only considers the unbundled/split offering of Secret Protection, not the bundled GHAS offering.
    # Note that this method returns:
    # - true for orgs that are on the Team plan **but haven't enabled GHSP on a private repo**!
    # - true for orgs on a secret protection trial.
    sig { returns(T::Boolean) }
    def secret_protection_purchased?
      T.bind(self, T.any(User, Organization, Business))

      return GitHub::Enterprise.license.secret_protection_enabled if GitHub.enterprise?
      return false if is_a?(Bot) || is_a?(Mannequin)

      entity = case self
      when Organization
        T.cast(self.billable_owner, T.any(Organization, Business))
      when Business
        self
      when User
        ::AdvancedSecurity::Features::User::AdvancedSecurity.new(self).get_business
      end
      return false if entity.nil?

      # note that this is just a feature flag check (but only for orgs)
      return true if ::EnterpriseCloudOnboard::SecretProtectionTrial.new(billable_entity: entity).enabled?
      entity.secret_protection_purchased_for_entity?
    end

    sig { params(sku: GitHub::Turboghas::SKU).returns(Integer) }
    def advanced_security_seats_used(sku: GitHub::Turboghas::SKU::Bundled)
      T.bind(self, T.any(User, Organization, Business))
      license = advanced_security_license_for_sku(sku:)
      return 0 unless license.purchased?
      license.entity_summary.active_committers
    end

    # Public: Returns the advanced security usage stats for this entity.
    # Returns a hash with the fields necessary to populate an advanced_security_trial.toggled event:
    # https://github.com/github/hydro-schemas/blob/main/proto/hydro/schemas/github/advanced_security/v0/advanced_security_trial_toggled.proto
    sig { returns(T::Hash[Symbol, Float]) }
    def advanced_security_usage_stats
      T.bind(self, T.any(Organization, Business))
      return {} unless advanced_security_license.purchased? || code_security.purchased? || secret_protection.purchased?

      total_committers = advanced_security_license.entity_summary.maximum_committers

      # Get the percentage of active committers for secret protection compared to the maximum number of committers for this entity
      secret_protection_committers_active = secret_protection.entity_summary.active_committers
      secret_protection_committers_covered_percent = (secret_protection_committers_active.to_f / total_committers) * 100

      # Get the percentage of active committers for code security compared to the maximum number of committers for this entity
      code_security_committers_active = code_security.entity_summary.active_committers
      code_security_committers_covered_percent = (code_security_committers_active.to_f / total_committers) * 100

      base_query = case self
      when Organization
        SecurityOverviewAnalytics::Repository
        .joins(:feature_status_summary)
        .where(organization_id: self.id)
      when Business
        SecurityOverviewAnalytics::Repository
        .joins(:feature_status_summary)
        .where(business_id: self.id)
      end

      query = base_query.select(
          Arel.sql("COUNT(*) AS total_repo_count"),
          Arel.sql("SUM(IF(`#{SecurityOverviewAnalytics::FeatureStatus.table_name}`.`dependabot_alerts_status` = 'ENABLED', 1, 0)) AS dependabot_alerts_enrolled_count"),
          Arel.sql("SUM(IF(`#{SecurityOverviewAnalytics::FeatureStatus.table_name}`.`dependabot_security_updates_status` = 'ENABLED', 1, 0)) AS dependabot_security_updates_enrolled_count"),
          Arel.sql("SUM(IF(`#{SecurityOverviewAnalytics::FeatureStatus.table_name}`.`code_scanning_alerts_status` = 'ENABLED', 1, 0)) AS code_scanning_alerts_enrolled_count"),
          Arel.sql("SUM(IF(`#{SecurityOverviewAnalytics::FeatureStatus.table_name}`.`code_scanning_pr_reviews_status` = 'ENABLED', 1, 0)) AS code_scanning_pr_reviews_enrolled_count"),
          Arel.sql("SUM(IF(`#{SecurityOverviewAnalytics::FeatureStatus.table_name}`.`code_scanning_auto_codeql_status` = 'ENABLED', 1, 0)) AS code_scanning_auto_codeql_enrolled_count"),
          Arel.sql("SUM(IF(`#{SecurityOverviewAnalytics::FeatureStatus.table_name}`.`secret_scanning_alerts_status` = 'ENABLED', 1, 0)) AS secret_scanning_alerts_enrolled_count"),
          Arel.sql("SUM(IF(`#{SecurityOverviewAnalytics::FeatureStatus.table_name}`.`secret_scanning_push_protection_status` = 'ENABLED', 1, 0)) AS secret_scanning_push_protection_enrolled_count"),
          Arel.sql("SUM(IF(`#{SecurityOverviewAnalytics::Repository.table_name}`.`visibility` != #{SecurityOverviewAnalytics::Repository.visibilities[:public]} AND `#{SecurityOverviewAnalytics::FeatureStatus.table_name}`.`secret_scanning_alerts_status` = 'ENABLED', 1, 0)) AS secret_protection_private_repos_enrolled_count"),
          Arel.sql("SUM(IF(`#{SecurityOverviewAnalytics::Repository.table_name}`.`visibility` != #{SecurityOverviewAnalytics::Repository.visibilities[:public]} AND `#{SecurityOverviewAnalytics::FeatureStatus.table_name}`.`code_scanning_alerts_status` = 'ENABLED', 1, 0)) AS code_security_private_repos_enrolled_count"),
        )

      db_result = ApplicationRecord::SecurityOverviewAnalytics.connection.select_one(query).to_hash.symbolize_keys
      total_repos = db_result[:total_repo_count]&.to_i || 0

      secret_protection_repos_enabled = db_result[:secret_scanning_alerts_enrolled_count]&.to_i || 0
      code_security_repos_enabled = db_result[:code_scanning_alerts_enrolled_count]&.to_i || 0
      code_scanning_pr_reviews_enabled = db_result[:code_scanning_pr_reviews_enrolled_count]&.to_i || 0
      code_scanning_auto_codeql_enabled = db_result[:code_scanning_auto_codeql_enrolled_count]&.to_i || 0
      dependabot_alerts_enabled = db_result[:dependabot_alerts_enrolled_count]&.to_i || 0
      dependabot_security_updates_enabled = db_result[:dependabot_security_updates_enrolled_count]&.to_i || 0
      secret_scanning_push_protection_enabled = db_result[:secret_scanning_push_protection_enrolled_count]&.to_i || 0
      secret_protection_private_repos_enabled = db_result[:secret_protection_private_repos_enrolled_count]&.to_i || 0
      code_security_private_repos_enabled = db_result[:code_security_private_repos_enrolled_count]&.to_i || 0

      {
        total_committers:,
        code_security_committers_active:,
        secret_protection_committers_active:,
        total_repos:,
        code_security_repos_enabled:,
        code_scanning_pr_reviews_enabled:,
        code_scanning_auto_codeql_enabled:,
        dependabot_alerts_enabled:,
        dependabot_security_updates_enabled:,
        secret_protection_repos_enabled:,
        secret_scanning_push_protection_enabled:,
        secret_protection_private_repos_enabled:,
        code_security_private_repos_enabled:,
      }
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
      T.bind(self, Business)

      # Cache is safe here because the result only depends on business_id + sku and only
      # changes when GHES instances upload Connect data (a separate background process on
      # an hours-to-days cadence). Without caching, mass security-configuration application
      # (e.g. 20k repos) fires 20k+ identical expensive JOIN queries against
      # business_user_accounts / enterprise_installation_user_accounts.
      cache_key = "advanced_security_business_user_ids:#{id}:#{sku}"
      GitHub.cache.fetch(cache_key, expires_in: 2.minutes, stats_key: "advanced_security_business_user_ids.cache") do
        advanced_security_business_user_accounts(sku:).where.not(user_id: nil).distinct.pluck(:user_id)
      end
    end

    # Public: Is the billable entity for GHAS
    def advanced_security_billable_entity?
      self == advanced_security_billable_entity
    end

    # The sig below causes failures in script/cibuild-snek-e2e-critical-label, for some ridiculous reason.
    # sig { returns(T.nilable(Billing::Types::OrgOrBusiness)) }
    memoize def advanced_security_billable_entity
      T.bind(self, T.any(User, Business))
      AdvancedSecurityLicense.billable_entity(self)
    end

    sig { void }
    def initialize_advanced_security_billing_config
      T.bind(self, T.any(Organization, Business))
      return unless FeatureFlag.vexi.enabled?(:ghas_stop_modifying_ghas_configuration_in_billing_onboarding_job, self, default: false)
      return if advanced_security_purchased?
      return unless advanced_security_billable_entity?
      return if self.is_a?(Organization) && !self.plan.business?
      set_customer_to_split_metered_offering(actor: User.ghost)
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

    # Indicates if there is a lock on using additional GHAS seats in metered mode
    sig { returns(T::Boolean) }
    def advanced_security_metered_usage_locked?
      return false if GitHub.enterprise?
      return false unless advanced_security_products_metered?

      # Metered usage can only be locked for bundled GHAS.
      return false if !advanced_security_products_bundled?

      T.bind(self, T.any(User, Organization, Business))
      return false if SecretScanning::Features::FeatureFlagHelper.feature_flag_enabled_in_hierarchy?(self, :disable_ghas_cpwu_lock)
      return true if self.feature_flag_enabled_or_raise?(:simulate_ghas_locked_metered_usage) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

      billable_owner = advanced_security_billable_entity
      return false if billable_owner.nil?
      billable_owner = T.let(billable_owner, T::any(Organization, Business))

      billable_owner.advanced_security_metered_usage_locked_for_entity?
    end

    # Indicates if there is a lock on using additional Secret Protection seats in metered mode
    sig { returns(T::Boolean) }
    def secret_protection_metered_usage_locked?
      return false if GitHub.enterprise?
      return false unless advanced_security_products_metered?

      T.bind(self, T.any(User, Organization, Business))
      return false if SecretScanning::Features::FeatureFlagHelper.feature_flag_enabled_in_hierarchy?(self, :disable_ghas_cpwu_lock)
      return true if self.feature_flag_enabled_or_raise?(:simulate_sp_locked_metered_usage) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

      billable_owner = advanced_security_billable_entity
      return false if billable_owner.nil?
      billable_owner = T.let(billable_owner, T::any(Organization, Business))

      billable_owner.advanced_security_metered_usage_locked? || billable_owner.secret_protection_metered_usage_locked_for_entity?
    end

    # Indicates if there is a lock on using additional Code Security seats in metered mode
    sig { returns(T::Boolean) }
    def code_security_metered_usage_locked?
      return false if GitHub.enterprise?
      return false unless advanced_security_products_metered?

      T.bind(self, T.any(User, Organization, Business))
      return false if SecretScanning::Features::FeatureFlagHelper.feature_flag_enabled_in_hierarchy?(self, :disable_ghas_cpwu_lock)
      return true if self.feature_flag_enabled_or_raise?(:simulate_cs_locked_metered_usage) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

      billable_owner = advanced_security_billable_entity
      return false if billable_owner.nil?
      billable_owner = T.let(billable_owner, T::any(Organization, Business))

      billable_owner.advanced_security_metered_usage_locked? || billable_owner.code_security_metered_usage_locked_for_entity?
    end

    # Returns the CPWU (can proceed with usage) reason for the GHAS metered usage lock, or nil if not locked
    sig { returns(T.nilable(String)) }
    def advanced_security_metered_usage_lock_reason
      return nil unless advanced_security_metered_usage_locked?

      advanced_security_billable_entity&.advanced_security_metered_usage_lock_reason_for_entity
    end

    # Returns the CPWU reason for the Secret Protection metered usage lock, or nil if not locked
    sig { returns(T.nilable(String)) }
    def secret_protection_metered_usage_lock_reason
      return nil unless secret_protection_metered_usage_locked?

      billable_owner = advanced_security_billable_entity
      return nil if billable_owner.nil?

      bundled_reason = billable_owner.advanced_security_metered_usage_lock_reason_for_entity
      return bundled_reason if bundled_reason

      billable_owner.secret_protection_metered_usage_lock_reason_for_entity
    end

    # Returns the CPWU reason for the Code Security metered usage lock, or nil if not locked
    sig { returns(T.nilable(String)) }
    def code_security_metered_usage_lock_reason
      return nil unless code_security_metered_usage_locked?

      billable_owner = advanced_security_billable_entity
      return nil if billable_owner.nil?

      bundled_reason = billable_owner.advanced_security_metered_usage_lock_reason_for_entity
      return bundled_reason if bundled_reason

      billable_owner.code_security_metered_usage_lock_reason_for_entity
    end
  end
end
