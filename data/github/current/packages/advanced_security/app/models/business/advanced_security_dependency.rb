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
    advanced_security_configurable? && (GitHub.enterprise? || !FeatureFlag.vexi.enabled_or_raise?(:advanced_security_circuit_breaker, advanced_security_license.billable_entity)) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
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
    response = GitHub::Turboghas.client.get_enterprise_users(Turboghas::Proto::GetEnterpriseUsersRequest.new(
      business_id: self.id,
      cursor: Turboghas::Proto::Cursor.new(offset: [0, page].max * page_size),
      limit: page_size,
    ))
    raise StandardError.new(response.error) if response.error.present?

    feature = AdvancedSecurity::Features::Business::AdvancedSecurity.new(T.bind(self, Business))
    total = feature.num_enterprise_users
    users = feature.get_enterprise_users(user_ids: response.data.users.map(&:id))
    users_by_id = users.index_by(&:id)

    num_without_ghas = total - response.data.count
    num_without_ghas = 0 if num_without_ghas < 0

    {
      users: response.data.users.map do |user|
        next if users_by_id[user.id].nil?
        {
          user: users_by_id[user.id],
          committer_count: user.active_committers,
          unique_committer_count: user.unique_committers,
        }
      end.compact,
      count: response.data.count,
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
    response = GitHub::Turboghas.client.get_organizations(Turboghas::Proto::GetOrganizationsRequest.new(
      business_id: self.id,
      cursor: Turboghas::Proto::Cursor.new(offset: [0, page].max * page_size),
      limit: page_size,
    ))
    raise StandardError.new(response.error) if response.error.present?
    orgs = self.organizations.where(id: response.data.organizations.map(&:id)).all.index_by(&:id)
    {
      orgs: response.data.organizations.map do |org|
        {
          organization: orgs.fetch(org.id),
          committer_count: org.active_committers,
          unique_committer_count: org.unique_committers,
        }
      end,
      total_orgs_count: response.data.count,
      num_orgs_without_ghas: total_orgs - response.data.count
    }
  end

  sig { params(actor: User, code_security_enablement_strategy: Symbol, skip_billing_config_changes: T::Boolean, licensing_model: Symbol).returns(T::Boolean) }
  def unbundle_ghas(actor:, code_security_enablement_strategy: :enable_code_security, skip_billing_config_changes: false, licensing_model: :metered)
    success = T.let(true, T::Boolean)

    # Notes:
    # 1. For GHES, all billing config changes are managed by the GHES license
    # 2. When setting billing config via stafftools, we'll skip re-setting it here.
    if GitHub.enterprise?
      SecurityConfiguration.advanced_security_billing_toggled(T.bind(self, Business), false)
    elsif !skip_billing_config_changes
      # Convert the business to the correct unbundled config based on their existing licensing model
      if licensing_model == :volume
        self.mark_advanced_security_as_purchased_for_entity_as_volume_unbundled(actor: actor)
        license_count = self.advanced_security_seats_for_entity
        self.set_secret_scanning_license_count(count: license_count, actor: actor)
        self.set_code_security_license_count(count: license_count, actor: actor)
      else
        self.set_customer_to_split_metered_offering(actor: actor)
      end
    end

    ghas_enabled_repos = {}
    self.organizations.each do |org|
      org.repositories.each do |repo|
        if GitHub.enterprise?
          # On GHES, an updated license has already been uploaded to the business,
          # preventing us from being able to use `Repository#advanced_security_enabled?`
          ghas_enabled_repos[repo.id] = repo if repo.config.enabled?(SecurityProduct::AdvancedSecurity::USER_ENABLED_KEY)
        else
          # On GHEC, we still avoid using `Repository#advanced_security_enabled?`
          # to allow this job to be re-run after it partially ran and failed.
          ghas_enabled_repos[repo.id] = repo if repo.config.enabled?(SecurityProduct::AdvancedSecurity::USER_ENABLED_KEY)
        end
      end
    end
    GitHub.logger.info("Finished calculating number of repositories that have GHAS enabled", {
      "code.namespace": "Business::AdvancedSecurityDependency",
      "code.function": "unbundle_ghas",
      "gh.business.id": self.id,
      "gh.ghas_enabled_repos_count": ghas_enabled_repos.count,
    })

    # Get a list of orgs, get security configs for the orgs, and unbundle them
    # number of repos we turned code-security on for
    number_of_repos_with_code_security_enabled = 0
    self.organizations.each do |org|
      with_write do
        # Set up Code Security service for each repo with GHAS currently enabled.
        # Preload all repository security configurations for this org’s repos
        repo_ids = org.repositories.pluck(:id)
        repository_security_configurations_map = RepositorySecurityConfiguration
          .joins(:security_configuration)
          .where(repository_id: repo_ids)
          .includes(:security_configuration)
          .index_by(&:repository_id)

        org.repositories.each do |repo|
          next unless ghas_enabled_repos[repo.id].present?

          # Get the security repo config attached to the repo. We need it for consistency checks later and
          # loading it already now allows should_enable_code_security_after_unbundling? to avoid API calls
          # in certain cases
          repository_security_configuration = repository_security_configurations_map[repo.id]
          applied_security_config = repository_security_configuration.security_configuration if repository_security_configuration&.applied?


          if should_enable_code_security_after_unbundling?(repo: repo, ghas_enabled_repos:, code_security_enablement_strategy:, applied_security_config:)
            begin
              CodeSecurity::Features::AdvancedSecurityHelper.enable_code_security!(actor: actor, repository: repo, options: { enablement_action: :sku_unbundling_transition.to_s })
              number_of_repos_with_code_security_enabled += 1
            rescue => error
              Failbot.report(error)
              GitHub.logger.error("Failed to enable Code Security on repository during unbundling", {
                exception: error,
                "code.namespace": "Business::AdvancedSecurityDependency",
                "code.function": "unbundle_ghas",
                "gh.business.id": self.id,
                "gh.organization.id": org.id,
                "gh.repository.id": repo.id
              })

              # There could now be a mismatch between a repo's current settings and its attached security configuration
              # We need to record this as an error on the RepositorySecurityConfiguration
              if !applied_security_config.nil? && applied_security_config.code_security_sku_enabled
                RepositorySecurityConfiguration.throttle_writes_with_retry do
                  reason = "Failed to enable Code Security when transitioning from Advanced Security."
                  repository_security_configuration&.update!(state: :failed, failure_reason: reason)
                end
              end
            end
          else
            # We could disable Code Security here, but we don't want to do that for now. We want to keep consistent
            # with the fact that we also don't disable Code Security if GHAS is disabled.

            # If an attached security config was demanding Code Security but we have decided not to enable it
            # we need to record this as an error on the RepositorySecurityConfiguration
            if !applied_security_config.nil? && applied_security_config.code_security_sku_enabled
              RepositorySecurityConfiguration.throttle_writes_with_retry do
                reason = "Code Security was chosen to not be enabled when transitioning from Advanced Security."
                repository_security_configuration&.update!(state: :failed, failure_reason: reason)
              end
            end
          end
        end
      end
    end

    GitHub.logger.info("Finished calculating number of repositories that have Code Security enabled", {
      "code.namespace": "Business::AdvancedSecurityDependency",
      "code.function": "unbundle_ghas",
      "gh.business.id": self.id,
      "gh.code_security_repo_count": number_of_repos_with_code_security_enabled,
    })

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
    if GitHub.enterprise?
      SecurityConfiguration.advanced_security_billing_toggled(T.bind(self, Business), true)
    elsif !skip_billing_config_changes
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

    # Get a list of orgs, get unbundled security configs for the orgs, and bundle them
    self.organizations.each do |org|
      with_write do
        # Set up GHAS for each repo with Code Security enabled
        org.repositories.each do |repo|
          if CodeSecurity::Features::AdvancedSecurityHelper.code_security_enabled?(repository: repo)
            begin
              repo.enable_advanced_security!(actor: actor, force: true)
            rescue => error
              Failbot.report(error)
              GitHub.logger.error("Failed to enable Advanced Security on repository during rebundling", {
                exception: error,
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

  private

  sig { params(repo: Repository, ghas_enabled_repos: T::Hash[Integer, Repository], code_security_enablement_strategy: Symbol, applied_security_config: T.nilable(SecurityConfiguration)).returns(T::Boolean) }
  def should_enable_code_security_after_unbundling?(repo:, ghas_enabled_repos:, code_security_enablement_strategy:, applied_security_config:)
    return false unless ghas_enabled_repos[repo.id].present?

    return true if code_security_enablement_strategy == :enable_code_security
    return false if code_security_enablement_strategy == :do_not_enable_code_security

    if code_security_enablement_strategy == :right_size
      # The calling code has already asserted that advanced security was enabled
      # For right-sizing we enable code security if the repo has any analysis
      # or code scanning default setup is enabled.

      # If we have a security config here we can potentially shortcut and avoid the API calls to Turboscan.
      # If code scanning default setup is enabled in the config it must be enabled on the repo
      return true if applied_security_config&.code_scanning_enabled?

      analyses = GitHub::Turboscan.analyses(repository_id: repo.id, limit: 1, most_recent: true)
      if analyses.nil? || analyses.error.present?
        GitHub.logger.error("Failed to check for analyses", {
          exception: analyses&.error,
          "code.namespace": "Business::AdvancedSecurityDependency",
          "code.function": "should_enable_code_security_after_unbundling?",
          "gh.business.id": self.id,
          "gh.repository.id": repo.id
        })
      end
      return true if analyses.present? && analyses.error.nil? && analyses.data.total_count > 0

      # If there is no analysis default setup could still be enabled in the waiting state
      begin
        return true if CodeScanning::AutoCodeql.new(repo).would_be_enabled_if_prerequisites_were_met?
      rescue => error
        GitHub.logger.error("Failed to check if default setup is enabled", {
          exception: error,
          "code.namespace": "Business::AdvancedSecurityDependency",
          "code.function": "should_enable_code_security_after_unbundling?",
          "gh.business.id": self.id,
          "gh.repository.id": repo.id
        })
      end

      # Either there is no reason to enable code security or we failed to check.
      # For the right-size option we default to not enabling code security in this case.
      return false
    end

    raise ArgumentError, "Unknown code security enablement strategy: #{code_security_enablement_strategy}"
  end
end
