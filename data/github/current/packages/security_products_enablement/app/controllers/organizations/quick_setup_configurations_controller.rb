# typed: true
# frozen_string_literal: true

module Organizations
  class QuickSetupConfigurationsController < Orgs::Controller
    include ApplicationController::VerifiedFetchDependency
    include ApplicationController::JsonDependency
    include ::SharedSecurityConfigurationsDependency
    include ::SecurityConfigurations::RepositoriesDependency
    include EnablementSettingsDependency

    sig { returns(String) }
    def self.react_bundle_name
      "security-products-enablement"
    end

    CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
      "Organizations::QuickSetupConfigurationsController#create",
      "Organizations::QuickSetupConfigurationsController#update",
    ]

    allow_verified_fetch only: [:create, :show, :update]

    before_action :check_feature_available
    before_action :manage_security_products_permission_required
    before_action :parse_json_params, only: [:create, :update]
    before_action :security_configuration, only: [:show, :update]
    around_action :set_log_context

    class ParameterError < StandardError; end
    rescue_from ParameterError do |exception|
      render json: { error: exception.message }, status: :unprocessable_entity
    end

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Mysql2,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Repositories,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Configurations,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Billing,
      ApplicationRecord::Collab,
      ApplicationRecord::Copilot,
      ApplicationRecord::Notify,
      ApplicationRecord::SecurityOverviewAnalytics,
      ApplicationRecord::SecurityProductsEnablement,
      only: [:new, :create, :update, :show, :repositories, :additional_license_usage]

    # GET /organizations/:organization_id/settings/security_products/quick_setup_configurations/new
    # Renders the first time Quick Setup configuration page - only shows when there is no existing configuration
    #
    sig { void }
    def new
      add_client_feature_flag(
        SecurityConfigurations::FeatureFlagHelper.client_feature_flags,
        entity: current_organization
      )

      render_react_app(
      payload: default_payload,
      title: "Settings · Set up Advanced Security · #{current_organization.name}",
      page_data: {
        selected_link: :security_products,
      },
      layout: "organization_settings",
    )
    end

    # POST /organizations/:organization_id/settings/security_products/quick_setup_configurations
    # Creates a new Quick Setup configuration and optionally applies it to repositories
    #
    # Parameters:
    #   - secret_protection: String (enabled/disabled/not_set) - State of secret protection features
    #   - code_security: String (enabled/disabled/not_set) - State of code security features
    #   - dependabot: String (enabled/disabled/not_set) - State of dependabot features
    #   - enforced: Boolean - Whether the configuration should be enforced
    #   - default_for_new_repositories: String (public/private/all/none) - Which types of new repositories
    #     this configuration should be set as default for (optional, defaults to none)
    #   - repository_selection: Array of Integer or "all"/"none" - Repository IDs to apply
    #     the configuration to, or special values: "all" for all repos, "none" to skip (required)
    #
    # Returns:
    #   - 201 Created with empty JSON body on success
    #   - 422 Unprocessable Entity with error details on validation failure
    sig { void }
    def create
      secret_protection = validate_state_param!(:secret_protection)
      code_security = validate_state_param!(:code_security)
      dependabot = validate_state_param!(:dependabot)
      repositories = validate_repository_selection_param!
      default_for_new_repositories = validate_default_for_new_repositories_param!
      enforced = validate_enforced_param!

      service = SecurityProductsEnablement::QuickSetupService.new(
        organization: current_organization,
        actor: current_user
      )

      config = service.create_and_apply_configuration(
        secret_protection:,
        code_security:,
        dependabot:,
        repositories:,
        default_for_new_repositories:,
        enforced:
      )

      if config.errors.any?
        log_and_track_errors(config)
        render json: { errors: serialize_errors(config.errors) }, status: :unprocessable_entity
      else
        render json: {}, status: :created
      end
    end

    # GET /organizations/:organization_id/settings/security_products/quick_setup_configurations/:id
    # Fetches Quick Setup configuration details with drift detection
    # This is used when opening the edit dialog to populate the form
    #
    # Parameters:
    #   - id: String - configuration ID
    #
    # Returns:
    #   - 200 OK with configuration details including:
    #     - secret_protection: enabled/disabled/not_set/custom
    #     - code_security: enabled/disabled/not_set/custom
    #     - dependabot: enabled/disabled/not_set/custom
    #     - repository_selection: Array of Integer or "all"/"none"/"not_applicable"
    #       - Array of repo IDs when some repos are attached
    #       - "all" when all org repos are attached
    #       - "none" when no repos are attached
    #       - "not_applicable" when too many repos to enumerate (>500)
    #     - default_for_new_repositories: public/private/all/none
    #     - enforced: true/false
    #   - 404 Not Found if configuration doesn't exist
    sig { void }
    def show
      # Get current Quick Setup states
      service = SecurityProductsEnablement::QuickSetupService.new(organization: current_organization, actor: current_user)
      states = service.detect_configuration_drift(security_configuration)

      # Get current default_for_new_repositories state
      default_record = SecurityConfigurationDefault.find_by(
        security_configuration_id: security_configuration.id,
        target: current_organization
      )
      default_for_new_repositories = if default_record
        SecurityProductsEnablement::QuickSetupService::DefaultForNewRepositories.from_booleans(
          default_for_public: default_record.default_for_new_public_repos,
          default_for_private: default_record.default_for_new_private_repos
        ).serialize
      else
        "none"
      end

      repository_selection = service.current_repository_selection(security_configuration)

      if repository_selection.selected?
        repository_selection = repository_selection.selected_repository_ids
      else
        repository_selection = repository_selection.value.serialize
      end

      render json: {
        secret_protection: states[:secret_protection],
        code_security: states[:code_security],
        dependabot: states[:dependabot],
        repository_selection:,
        default_for_new_repositories:,
        enforced: security_configuration.enforced?(current_organization)
      }, status: :ok
    end

    # PATCH /organizations/:organization_id/settings/security_products/quick_setup_configurations/:id
    # Updates an existing Quick Setup configuration
    # This is used when the user saves changes from the edit dialog
    #
    # Parameters:
    #   - id: String - configuration ID
    #   - secret_protection: String (enabled/disabled/not_set/custom) - State of secret protection features (optional)
    #   - code_security: String (enabled/disabled/not_set/custom) - State of code security features (optional)
    #   - dependabot: String (enabled/disabled/not_set/custom) - State of dependabot features (optional)
    #   - default_for_new_repositories: String (public/private/all/none) - Which types of new repositories
    #     this configuration should be set as default for (optional, defaults to none)
    #   - enforced: Boolean - Whether the configuration should be enforced (required)
    #   - repository_selection: Array of Integer or "all"/"none"/"not_applicable" - Repository IDs to update
    #     attachments for, or special values: "all" for all repos, "none" to detach all,
    #     "not_applicable" to skip repository updates (required)
    #
    # Note: For enterprise and GHR (global) configurations, service states (secret_protection,
    # code_security, dependabot) are ignored — only policy changes (enforcement, defaults,
    # repository attachments) are applied at the org level.
    #
    # Returns:
    #   - 200 OK with empty JSON body on success
    #   - 422 Unprocessable Entity with error details on validation failure
    sig { void }
    def update
      config = security_configuration

      secret_protection = params[:secret_protection].present? ? validate_state_param!(:secret_protection) : nil
      code_security = params[:code_security].present? ? validate_state_param!(:code_security) : nil
      dependabot = params[:dependabot].present? ? validate_state_param!(:dependabot) : nil
      default_for_new_repositories = validate_default_for_new_repositories_param!
      enforced = validate_enforced_param!
      repositories = validate_repository_selection_param!
      service = SecurityProductsEnablement::QuickSetupService.new(
        organization: current_organization,
        actor: current_user
      )

      service.update_configuration(
        configuration: config,
        repositories:,
        default_for_new_repositories:,
        secret_protection:,
        code_security:,
        dependabot:,
        enforced:
      )

      if config.errors.any?
        log_and_track_errors(config)
        render json: { errors: serialize_errors(config.errors) }, status: :unprocessable_entity
      else
        render json: {}, status: :ok
      end
    end

    # GET /organizations/:organization_id/settings/security_products/quick_setup_configurations/repositories
    # Returns a list of repositories in the organization with license info and optional configuration status
    # Limited to first 500 repositories
    #
    # Parameters:
    #   - q: String (optional) - Search query for filtering repositories
    #   - configuration_id: Integer (optional) - Configuration ID to check which repositories have it applied
    #
    # Returns:
    #   - 200 OK with repository list including:
    #     - repositories: Array of repository objects with:
    #       - id, name, visibility, archived, pushed_at
    #       - licenses_required: Integer or nil (for GHAS license calculation)
    #       - security_configuration: Hash or nil (current configuration details)
    #       - security_features_enabled: Boolean
    #       - configuration_applied: Boolean (only present when configuration_id parameter is provided)
    #       - additionalSecretProtectionCommitterIds: Array of Integer (committer IDs that would be added to billing)
    #       - additionalCodeSecurityCommitterIds: Array of Integer (committer IDs that would be added to billing)
    #     - total_repository_count: Total number of repositories matching the query
    sig { void }
    def repositories # rubocop:todo GitHub/UseRestfulActions
      search_query = params[:q].to_s
      configuration_id = params[:configuration_id].present? ? params[:configuration_id].to_i : nil

      # Validate configuration ownership if configuration_id is provided
      if configuration_id
        targets = [current_organization, current_organization.business].compact
        config = find_security_configuration(targets, id: configuration_id)
      end

      # Note: The ES search path in RepoQuery#prune_results calls repo_is_searchable? → routed? →
      # dgit_read_routes for every repo in the result set, triggering a per-repository Spokes RPC
      # with no batch alternative. Therefore we are limiting to 250 to keep response time reasonable.
      result = serialized_repositories(
        organization: current_organization,
        user: current_user,
        user_session: user_session,
        cap_filter: cap_filter,
        search_query: search_query,
        current_page: 1,
        per_page: 250,
        compute_security_features_enabled: false # this can be slow with a bunch of repos and we don't need
      )

      repositories = result[:repositories]

      # Add configuration_applied and committer data to repositories
      add_repository_metadata(repositories, config:)

      render json: {
        repositories: repositories,
        total_repository_count: result[:total_repository_count],
      }, status: :ok
    end

    # GET /organizations/:organization_id/settings/security_products/quick_setup_configurations/additional_license_usage
    # Returns the additional license usage that would be incurred by enabling all unbundled SKUs
    # across all repositories in the organization
    #
    # Returns:
    #   - 200 OK with license usage data:
    #     - secret_protection: { license_count: Integer } (only if SKU purchased)
    #     - code_security: { license_count: Integer } (only if SKU purchased)
    #   - 200 OK with empty body for bundled orgs (they use a single bundled license)
    sig { void }
    def additional_license_usage # rubocop:todo GitHub/UseRestfulActions
      license_usage = build_license_usage_data

      render json: license_usage || {}, status: :ok
    end

    private

    # Builds license usage increase data for unbundled SKUs
    # Returns nil for bundled orgs (they use a single bundled license)
    # Each SKU is wrapped in an object to allow adding additional fields later (e.g., total_cost)
    sig { returns(T.nilable(T::Hash[Symbol, T::Hash[Symbol, Integer]])) }
    def build_license_usage_data
      return nil if current_organization.advanced_security_products_bundled?

      usage = {}

      if current_organization.advanced_security_license_for_sku(sku: GitHub::Turboghas::SKU::SecretSecurity).purchased?
        usage[:secret_protection] = {
          license_count: quick_setup_licensing_service.increased_license_usage_for_sku(
            GitHub::Turboghas::SKU::SecretSecurity
          )
        }
      end

      if current_organization.advanced_security_license_for_sku(sku: GitHub::Turboghas::SKU::CodeSecurity).purchased?
        usage[:code_security] = {
          license_count: quick_setup_licensing_service.increased_license_usage_for_sku(
            GitHub::Turboghas::SKU::CodeSecurity
          )
        }
      end

      usage.empty? ? nil : usage
    end

    sig { params(repositories: T::Array[T::Hash[Symbol, T.untyped]], config: T.nilable(SecurityConfiguration)).void }
    def add_repository_metadata(repositories, config: nil)
      return if repositories.empty?

      # Fetch configuration_applied data if config is provided
      applied_repo_ids = if config
        RepositorySecurityConfiguration
          .where(security_configuration_id: config.id, repository_id: repositories.map { |r| r[:id] })
          .applied
          .pluck(:repository_id)
          .to_set
      end

      # Fetch committer data for purchased features (skip for bundled orgs)
      unless current_organization.advanced_security_products_bundled?
        secret_protection_purchased = current_organization
          .advanced_security_license_for_sku(sku: GitHub::Turboghas::SKU::SecretSecurity)
          .purchased?
        code_security_purchased = current_organization
          .advanced_security_license_for_sku(sku: GitHub::Turboghas::SKU::CodeSecurity)
          .purchased?

        secret_protection_committers = if secret_protection_purchased
          quick_setup_licensing_service.fetch_committer_data_for_feature(
            repositories,
            GitHub::Turboghas::SKU::SecretSecurity
          )
        else
          {}
        end

        code_security_committers = if code_security_purchased
          quick_setup_licensing_service.fetch_committer_data_for_feature(
            repositories,
            GitHub::Turboghas::SKU::CodeSecurity
          )
        else
          {}
        end
      end

      repositories.each do |repo|
        repo_id = repo[:id]

        # Add configuration_applied if config was provided
        repo[:configuration_applied] = applied_repo_ids.include?(repo_id) if applied_repo_ids

        # Add committer data if available
        if secret_protection_committers
          secret_ids = secret_protection_committers[repo_id]
          repo[:additionalSecretProtectionCommitterIds] = secret_ids if secret_ids
        end

        if code_security_committers
          code_ids = code_security_committers[repo_id]
          repo[:additionalCodeSecurityCommitterIds] = code_ids if code_ids
        end
      end
    end

    sig { returns(SecurityProductsEnablement::QuickSetupService::LicensingService) }
    memoize def quick_setup_licensing_service
      SecurityProductsEnablement::QuickSetupService::LicensingService.new(
        organization: current_organization
      )
    end

    def check_feature_available
      render_404 unless current_organization&.has_organization_quick_setup?
    end

    sig { params(service: Symbol).returns(T.nilable(SecurityProductsEnablement::QuickSetupService::State)) }
    def validate_state_param!(service)
      state = T.let(nil, T.nilable(SecurityProductsEnablement::QuickSetupService::State))
      if params[service].present?
        state = SecurityProductsEnablement::QuickSetupService::State.try_deserialize(params[service])
        raise ParameterError, "Invalid state for #{service}" if state.nil?
      end

      state
    end

    # Validates repository_selection parameter
    # Required - must be provided explicitly
    sig { returns(SecurityProductsEnablement::RepositorySelection) }
    def validate_repository_selection_param!
      if params[:repository_selection].nil?
        raise ParameterError, "repository_selection is required"
      elsif params[:repository_selection] == "not_applicable"
        SecurityProductsEnablement::RepositorySelection.not_applicable
      elsif params[:repository_selection] == "none"
        SecurityProductsEnablement::RepositorySelection.none
      elsif params[:repository_selection] == "all"
        SecurityProductsEnablement::RepositorySelection.all
      elsif params[:repository_selection].is_a?(Array)
        ids = params[:repository_selection].map(&:to_i)
        raise ParameterError, "Too many repository ids provided (max #{SecurityProductsEnablement::RepositorySelection::MAX_REPOSITORY_IDS_FOR_QUICK_SETUP})" if ids.size > SecurityProductsEnablement::RepositorySelection::MAX_REPOSITORY_IDS_FOR_QUICK_SETUP
        in_org_ids = T.let(current_organization.repositories.where(id: ids).pluck(:id), T::Array[Integer])

        raise ParameterError, "No valid repository ids provided" if in_org_ids.empty?
        SecurityProductsEnablement::RepositorySelection.selected(in_org_ids)
      else
        raise ParameterError, "Invalid value for repository_selection"
      end
    end

    sig { returns(T::Boolean) }
    def validate_enforced_param!
      if params[:enforced].nil?
        false
      elsif params[:enforced].is_a?(TrueClass) || params[:enforced].is_a?(FalseClass)
        params[:enforced]
      else
        raise ParameterError, "Invalid value for enforced"
      end
    end

    sig { returns(SecurityProductsEnablement::QuickSetupService::DefaultForNewRepositories) }
    def validate_default_for_new_repositories_param!
      if params[:default_for_new_repositories].blank?
        SecurityProductsEnablement::QuickSetupService::DefaultForNewRepositories::None
      else
        value = SecurityProductsEnablement::QuickSetupService::DefaultForNewRepositories.try_deserialize(params[:default_for_new_repositories])
        raise ParameterError, "Invalid value for default_for_new_repositories" if value.nil?
        value
      end
    end
  end
end
