# typed: true
# frozen_string_literal: true

module Repository::SecurityProductsDependency
  extend ActiveSupport::Concern

  extend T::Helpers
  requires_ancestor { Repository }

  included do
    T.bind(self, T.class_of(Repository))
    has_one :repository_security_configuration, dependent: :destroy
    has_one :security_configuration, through: :repository_security_configuration
  end

  sig { returns(RepositorySecurityConfiguration) }
  def repository_security_configuration!
    T.must(repository_security_configuration)
  end

  sig { returns(SecurityConfiguration) }
  def security_configuration!
    T.must(security_configuration)
  end

  # Enables / disables security products for a repository based on automatic opt-in configuration
  # This method is called when a repository is created and applies
  # default settings for security products defined at the org and user level
  sig { params(user: User, is_fork: T::Boolean).returns(SecurityProduct::Result) }
  def setup_security_products_on_creation(user, is_fork)
    owner = T.must(self.owner)

    # When security configurations are enabled, skip this enablement in favor of apply its default config:
    return SecurityProduct::Result.new(true) if owner.security_configurations_enabled?

    # skip instrumentation here and let HydroSecurityCenterRepositoryCreatedJob handle it
    T.bind(self, Repository)
    SecurityProduct::ServiceManager.new(self).toggle_services_with_form_inputs(
      user,
      params: all_security_product_options(is_fork),
      skip_instrumentation: true,
    )
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def default_settings_for_features_not_in_security_configuration
    owner = T.must(self.owner)

    options = {}
    options[:is_repo_creation] = true

    # Dependabot on Actions
    options[:dependabot_on_actions_enabled] = owner.dependabot_on_actions_enabled_for_new_repos? ? "1" : "0"
    options[:dependabot_self_hosted_enabled] = owner.dependabot_self_hosted_enabled_for_new_repos? ? "1" : "0"

    # Dependabot Autofix
    options[:dependabot_autofix_enabled] = owner.dependabot_autofix_enabled_for_new_repos? ? "1" : "0"

    # Innersource Advisories
    options[:innersource_advisories_enabled] = owner.innersource_advisories_enabled_for_new_repos? ? "1" : "0"

    # If we are enabling vulnerability updates as part of Repository creation,
    # we need to set a flag to indicate the Dependabot GitHub App should not be
    # installed yet.
    #
    # The installation should be deferred until at least one supported manifest
    # file is pushed so we do not produce webhook events until the Repository
    # actively able to use the feature.
    options[:skip_vulnerability_updates_dependabot_install] = true

    options
  end

  sig { params(business: Business, actor: User).returns(SecurityProduct::Result) }
  def setup_security_products_based_on_business_defaults(business, actor)
    params = {}
    params[:vulnerability_alerts_enabled] = "1" if business.security_alerts_enabled_for_new_repos?
    params.merge!(get_advanced_security_options)
    params.merge!(get_secret_scanning_options)

    return SecurityProduct::Result.new(false, :no_business_defaults) if params.empty?

    params[:is_repo_creation] = true

    T.bind(self, Repository)
    SecurityProduct::ServiceManager.new(self).toggle_services_with_form_inputs(actor, params:, skip_instrumentation: true)
  end

  private

  sig { params(is_fork: T::Boolean).returns(T::Hash[Symbol, T.untyped]) }
  def all_security_product_options(is_fork)
    options = Hash.new

    # Advanced Security
    options.merge!(get_advanced_security_options)

    # Secret Scanning
    options.merge!(get_secret_scanning_options)

    # Historically, security product settings have not been carried over to forked
    # repositories. Due to that, we'll incrementally support enabling security products
    # on forked repositories. For now, we'll return the options hash with only
    # supported security products.
    return options if is_fork

    # Dependency graph
    options.merge!(get_dependency_graph_options)

    # Vulnerability reporting
    options.merge!(get_vulnerability_reporting_options)

    # New features should be added to the method below when:
    # - They can be automatically enabled for new repos
    # - And for organizations, the features won't be part of security configurations, but instead stay on the Global settings page
    options.merge!(default_settings_for_features_not_in_security_configuration)

    options
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def get_dependency_graph_options
    owner = T.must(self.owner)
    options = {}

    if GitHub.dependency_graph_enabled?
      # For GHES, dependency graph is enabled on all new repos by default
      if GitHub.enterprise?
        options[:dependency_graph_enabled] = "1"
      # DG might be enabled on new private repos if the owner has enabled that
      elsif private? || ::SecurityProduct::DependencyGraph.always_default_off_enabled?(self)
        options[:dependency_graph_enabled] = owner.dependency_graph_enabled_for_new_repos? ? "1" : "0"
      end
    end

    options
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def get_advanced_security_options
    owner = T.must(self.owner)
    options = {}

    if private? || GitHub.enterprise?
      # Advanced security is only enabled on new private or Enterprise repos if the owner has purchased it
      if owner.advanced_security_purchased?
        options[:advanced_security_enabled] = "1" if enable_advanced_security_on_new_repo?
      end
    end

    options
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def get_vulnerability_reporting_options
    owner = T.must(self.owner)
    options = {}

    # Dependabot alerts
    options[:vulnerability_alerts_enabled] = owner.security_alerts_enabled_for_new_repos? ? "1" : "0"

    # Dependabot security updates
    options[:vulnerability_updates_enabled] = owner.vulnerability_updates_enabled_for_new_repos? ? "1" : "0"

    # Grouped security updates
    options[:vulnerability_updates_grouping_enabled] = owner.vulnerability_updates_grouping_enabled_for_new_repos? ? "1" : "0"

    # Private vulnerability reporting
    options[:private_vulnerability_reporting_enabled] = owner.private_vulnerability_reporting_enabled_for_new_repos? ? "1" : "0"

    options
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def get_secret_scanning_options
    owner = T.must(self.owner)

    options = {}
    if owner.organization?
      org_token_scanning = SecretScanning::Features::Org::TokenScanning.new(owner)
      T.bind(self, Repository)
      repo_token_scanning = SecretScanning::Features::Repo::TokenScanning.new(self)
      return {} unless org_token_scanning.feature_available? && repo_token_scanning.feature_available?

      # Because the org or repo have considered Secret Scanning an available feature,
      # we can safely make assume that one of these is true:
      # * The org has purchased advanced security
      # * The repository is public
      # * This is not a private repository for a non-GHAS repo
      enable_secret_scanning = true

      # However, if the org has purchased advanced security, then we need to ensure that Advanced Security is
      # set to be enabled on new repositories. If it is not, then we should not enable Secret Scanning.
      # This only applies for non-public repos within the org, that require advanced security to be enabled
      # first.
      # When turning on advanced security, this will also turn on secret scanning
      # This should make it redundant. However, we are keeping this here for now.
      if owner.advanced_security_purchased? && !public?
        enable_secret_scanning = enable_advanced_security_on_new_repo?
      end

      return {} unless enable_secret_scanning
      return {} if owner.business.nil?
      return {} unless SecretScanning::Features::Business::TokenScanning.new(owner.business).secret_scanning_enabled_for_new_repos?

      options[:token_scanning_enabled] = "1"

      # Push protection
      push_protection = SecretScanning::Features::Business::PushProtection.new(owner.business)
      if push_protection.enabled_for_new_repos?
        options[:token_scanning_push_protection_enabled] = "1"
      end

      options[:token_scanning_validity_checks_enabled] = "1" if SecretScanning::Features::Business::ValidityChecks.new(owner.business).enabled_for_new_repos?
      options[:token_scanning_lower_confidence_patterns_enabled] = "1" if SecretScanning::Features::Business::LowerConfidencePatterns.new(owner.business).enabled_for_new_repos?
    elsif owner.user?
      # The only user-owned repositories we support are those owned
      # by an enterprise-managed-business, or the global business in the case of GHES
      # Otherwise, the user doesn't get a say whether secret-scanning is turned on
      user_token_scanning = SecretScanning::Features::User::TokenScanning.new(owner)
      if user_token_scanning.can_enable_for_new_repos?
        return {} unless enable_advanced_security_on_new_repo?

        ghas_for_users = AdvancedSecurity::Features::User::AdvancedSecurity.new(owner)
        business = ghas_for_users.get_business
        return {} if business.nil?

        biz_token_scanning = SecretScanning::Features::Business::TokenScanning.new(business)
        return {} unless biz_token_scanning.secret_scanning_enabled_for_new_repos? || user_token_scanning.secret_scanning_enabled_for_new_repos?

        options[:token_scanning_enabled] = "1"

        biz_push_protection = SecretScanning::Features::Business::PushProtection.new(business)
        user_push_protection = SecretScanning::Features::User::PushProtection.new(owner)

        if biz_push_protection.enabled_for_new_repos? || user_push_protection.enabled_for_new_repos?
          options[:token_scanning_push_protection_enabled] = "1"
        end
      elsif public?
        # Eventually this branch will always kick in for public repositories
        # When the flag is enabled for the user, they do not have a choice to turn it off

        # All public repos get secret scanning + push protection turned on
        options[:token_scanning_enabled] = "1"
        options[:token_scanning_push_protection_enabled] = "1"
        return options
      end
    end
    options
  end
end
