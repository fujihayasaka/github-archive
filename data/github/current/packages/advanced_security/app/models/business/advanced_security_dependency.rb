# typed: true
# frozen_string_literal: true

module Business::AdvancedSecurityDependency
  include AdvancedSecurity::Public::Subscription
  include AdvancedSecurity::Public::Pricing

  extend T::Helpers
  requires_ancestor { Business }

  ORG_BATCH_SIZE = 100
  REPO_BATCH_SIZE = 1000
  NEW_REPOS_ENABLED_KEY = "advanced_security.new_business_repos"
  NEW_USER_NAMESPACE_REPOS_ENABLED_KEY = "advanced_security.new_user_namespace_repos"
  SECRET_SCANNING_NEW_REPOS_KEY = "secret_scanning.new_business_repos_enable".freeze

  def advanced_security_configurable?
    advanced_security_purchased?
  end

  def enforce_advanced_security_committers_limits?
    advanced_security_configurable? && (GitHub.enterprise? || !GitHub.flipper[:advanced_security_circuit_breaker].enabled?(advanced_security_license.billable_entity))
  end

  def enable_advanced_security_on_new_repos(actor:)
    config.enable(NEW_REPOS_ENABLED_KEY, actor)
  end

  def disable_advanced_security_on_new_repos(actor:)
    config.delete(NEW_REPOS_ENABLED_KEY, actor)
  end

  def advanced_security_enabled_on_new_repos?
    return false unless advanced_security_purchased?
    config.enabled?(NEW_REPOS_ENABLED_KEY)
  end

  def enable_advanced_security_on_new_user_namespace_repos(actor:)
    config.enable(NEW_USER_NAMESPACE_REPOS_ENABLED_KEY, actor)
  end

  def disable_advanced_security_on_new_user_namespace_repos(actor:)
    config.delete(NEW_USER_NAMESPACE_REPOS_ENABLED_KEY, actor)
  end

  def advanced_security_enabled_on_new_user_namespace_repos?
    return false unless advanced_security_purchased?
    config.enabled?(NEW_USER_NAMESPACE_REPOS_ENABLED_KEY)
  end

  def get_advanced_security_enterprise_users_and_counts(actor:, page:, page_size: 10)
    response = GitHub::Turboghas.client.get_enterprise_users(
      business_id: self.id,
      cursor: { offset: [0, page].max * page_size },
      limit: page_size,
    )
    raise StandardError.new(response.error) if response.error.present?

    feature = AdvancedSecurity::Features::Business::AdvancedSecurity.new(T.bind(self, Business))
    total = feature.num_enterprise_users
    users = feature.get_enterprise_users(user_ids: response.data&.users.map(&:id))
    users_by_id = users.index_by(&:id)

    num_without_ghas = total - response.data&.count
    num_without_ghas = 0 if num_without_ghas < 0

    {
      users: response.data&.users.map do |user|
        next if users_by_id[user.id].nil?
        {
          user: users_by_id[user.id],
          committer_count: user.active_committers,
          unique_committer_count: user.unique_committers,
        }
      end.compact,
      count: response.data&.count,
      num_without_ghas: num_without_ghas
    }
  end

  # Returns a page from the list of orgs owned by this business,
  # with the following data:
  # {organization:, committer_count:, unique_committer_count:}
  # The list is ordered by organization name.
  # "unique committer count" is users who have committed to this org but not
  # to any other org covered by this GHAS license.
  #
  # Actual return value is a hash of the form {orgs:, total_orgs_count:, num_orgs_without_ghas:}
  # where orgs: is the page of org data described above, and
  # total_orgs_count: is the total number of GHAS orgs owned by this business (total, not just the number on the current page).
  # num_orgs_without_ghas: is the number of orgs owned by this business which don't contain any repos for which GHAS is enabled
  #
  # page is 0-based
  def get_advanced_security_orgs_and_counts(page:, page_size: 10)
    total_orgs = self.organizations.count
    response = GitHub::Turboghas.client.get_organizations(
      business_id: self.id,
      cursor: { offset: [0, page].max * page_size },
      limit: page_size,
    )
    raise StandardError.new(response.error) if response.error.present?
    orgs = self.organizations.where(id: response.data&.organizations.map(&:id)).all.index_by(&:id)
    {
      orgs: response.data&.organizations.map do |org|
        {
          organization: orgs.fetch(org.id),
          committer_count: org.active_committers,
          unique_committer_count: org.unique_committers,
        }
      end,
      total_orgs_count: response.data&.count,
      num_orgs_without_ghas: total_orgs - response.data&.count
    }
  end

  # Gets the total number of active users for the high watermark sku
  sig { params(sku: GitHub::Turboghas::SKU).returns(Integer) }
  def advanced_security_billable_licenses(sku:)
    ghes_committers = self.advanced_security_license_for_sku(sku:).ghes_committers
    response = GitHub::Turboghas.client.get_meter_emissions(
      **sku.to_proto,
      entity_type: :ENTITY_TYPE_BUSINESS,
      entity_id: self.id,
      customer_id: self.customer_id,
      additional_user_ids: ghes_committers&.user_ids,
      current_billing_period_started_at: current_metered_billing_cycle_starts_at.to_time,
    )

    return 0 if response.nil? || response.error.present?
    response.data.total
  end

  sig { params(actor: User, skip_billing_config_changes: T::Boolean).returns(T::Boolean) }
  def unbundle_ghas(actor:, skip_billing_config_changes: false)
    success = T.let(true, T::Boolean)

    # Notes:
    # 1. For bundled vol -> unbundled metered transitions, billing config changes are already
    # handled by Licensing::TransitionEnterpriseToMeteredLicensingJob, so we needn't make any more
    # changes.
    # 2. For GHES, all billing config changes are managed by the GHES license
    unless skip_billing_config_changes || GitHub.enterprise?
      # Convert the business to the correct unbundled config based on their existing licensing model
      case advanced_security_enabled_type = self.advanced_security_enabled_type_for_entity
      when Configurable::AdvancedSecurityBillingConfig::GHAS_VOLUME
        self.mark_advanced_security_as_purchased_for_entity_as_volume_unbundled(actor: actor)
      when Configurable::AdvancedSecurityBillingConfig::GHAS_METERED
        self.set_customer_to_split_metered_offering(actor: actor)
      else
        raise ArgumentError, "Business does not have the right licensing model for GHAS unbundling"
      end
    end

    # Get security configs for business, and unbundle them
    enterprise_security_configurations = SecurityConfiguration.where(target: self)

    enterprise_security_configurations.each do |configuration|
      unbundled_config = configuration.unbundle!
      success = false unless log_and_report_bundle_state_change(unbundled_config)
    end

    # Get a list of orgs, get security configs for the orgs, and unbundle them
    self.organizations.each do |org|
      with_write do
        org_security_configurations = SecurityConfiguration.where(target: org)
        org_security_configurations.each do |configuration|
          unbundled_config = configuration.unbundle!
          success = false unless log_and_report_bundle_state_change(unbundled_config)
        end

        # Set up Code Security service for each repo with GHAS currently enabled.
        org.repositories.each do |repo|
          if repo.advanced_security_enabled?
            begin
              repo.enable_code_security!(actor: actor)
            rescue => error
              Failbot.report(error)
              GitHub.logger.error("Failed to enable Code Security on repository during unbundling", {
                exception: error.message,
                "code.namespace": "Business::AdvancedSecurityDependency",
                "code.function": "unbundle_ghas",
                "gh.business.id": self.id,
                "gh.organization.id": org.id,
                "gh.repository.id": repo.id
              })
            end
          end
        end
      end
    end

    success
  end

  sig { params(actor: User, skip_billing_config_changes: T::Boolean).returns(T::Boolean) }
  def rebundle_ghas(actor:, skip_billing_config_changes: false)
    success = T.let(true, T::Boolean)

    # Notes:
    # 1. For unbundled metered -> bundled metered rollback transitions triggered via stafftools, billing config changes are already
    # handled by Licensing::TransitionEnterpriseToVolumeLicensingJob, so we needn't make any more
    # changes.
    # 2. For GHES, all billing config changes are managed by the GHES license.
    unless skip_billing_config_changes || GitHub.enterprise?
      # Convert the business to the correct bundled config based on their existing licensing model
      case advanced_security_enabled_type = self.advanced_security_enabled_type_for_entity
      when Configurable::AdvancedSecurityBillingConfig::SPLIT_VOLUME
        self.mark_advanced_security_as_purchased_for_entity(actor: actor)
      when Configurable::AdvancedSecurityBillingConfig::SPLIT_METERED
        self.mark_advanced_security_as_metered_for_entity(actor: actor)
      else
        raise ArgumentError, "Business does not have the right licensing model for GHAS rebundling"
      end
    end

    # Get unbundled security configs for business, and bundle them
    enterprise_unbundled_security_configurations = UnbundledSecurityConfiguration.where(target: self)

    enterprise_unbundled_security_configurations.each do |configuration|
      rebundled_config = configuration.bundle!
      success = false unless log_and_report_bundle_state_change(rebundled_config)
    end

    # Get a list of orgs, get unbundled security configs for the orgs, and bundle them
    self.organizations.each do |org|
      with_write do
        org_unbundled_security_configurations = UnbundledSecurityConfiguration.where(target: org)
        org_unbundled_security_configurations.each do |configuration|
          rebundled_config = configuration.bundle!
          success = false unless log_and_report_bundle_state_change(rebundled_config)
        end

        # Set up GHAS for each repo with Code Security enabled
        org.repositories.each do |repo|
          if repo.code_security_enabled?
            begin
              repo.enable_advanced_security!(actor: actor)
            rescue => error
              Failbot.report(error)
              GitHub.logger.error("Failed to enable Advanced Security on repository during rebundling", {
                exception: error.message,
                "code.namespace": "Business::AdvancedSecurityDependency",
                "code.function": "rebundle_ghas",
                "gh.business.id": self.id,
                "gh.organization.id": org.id,
                "gh.repository.id": repo.id
              })
            end
          end
        end
      end
    end

    success
  end

  sig { params(security_config: SecurityConfiguration).returns(T::Boolean) }
  def log_and_report_bundle_state_change(security_config)
    bundle_state_change_action = security_config.is_a?(UnbundledSecurityConfiguration) ? "unbundle" : "rebundle"
    if security_config.errors.any?
      Failbot.report("Failed to #{bundle_state_change_action} security configuration", {
        "error": security_config.errors.to_hash,
        "security_configuration_id": security_config.id,
        "business_id": self.id
      })
      GitHub.logger.error("Failed to #{bundle_state_change_action} security configuration", {
        exception: security_config.errors.to_hash,
        "code.namespace": "Business::AdvancedSecurityDependency",
        "code.function": "#{bundle_state_change_action}_ghas",
        "gh.security_configuration.id": security_config.id,
        "gh.business.id": self.id
      }
      )

      false
    else
      GitHub.logger.info("Successfully #{bundle_state_change_action}d security configuration", {
        "code.namespace": "Business::AdvancedSecurityDependency",
        "code.function": "#{bundle_state_change_action}_ghas",
        "gh.security_configuration.id": security_config.id,
        "gh.business.id": self.id,
      }
      )

      true
    end
  end
end
