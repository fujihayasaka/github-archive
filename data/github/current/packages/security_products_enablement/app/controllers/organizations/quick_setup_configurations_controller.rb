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

    before_action :check_feature_flag
    before_action :manage_security_products_permission_required
    before_action :parse_json_params, only: [:create, :update]
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
      only: [:new, :create, :update, :show, :repositories]

    # GET /organizations/:organization_id/settings/security_products/quick_setup_configurations/new
    # Renders the first time Quick Setup configuration page - only shows when there is no existing configuration
    #
    sig { void }
    def new
      add_client_feature_flag(SecurityConfigurations::FeatureFlagHelper.client_feature_flags, entity: current_organization)

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
    #   - repository_ids: Array of Integer or "all" - Repository IDs to apply the configuration to, or "all" for all repos
    #
    # Returns:
    #   - 201 Created with empty JSON body on success
    #   - 422 Unprocessable Entity with error details on validation failure
    sig { void }
    def create
      # Convert "all" string to :all symbol for service call
      repository_ids = params[:repository_ids]
      repository_ids = :all if repository_ids == "all"

      # Validate repository ownership before processing
      if repository_ids.is_a?(Array) && repository_ids.any?
        validated_ids = validate_repository_ownership(repository_ids)

        if validated_ids.length != repository_ids.length
          invalid_ids = repository_ids - validated_ids
          render json: {
            error: "Invalid repository IDs: #{invalid_ids.join(', ')}. These repositories either don't exist or don't belong to this organization."
          }, status: :unprocessable_entity
          return
        end

        repository_ids = validated_ids
      end

      begin
        config = SecurityProductsEnablement::QuickSetupService.create_and_apply_configuration(
          organization: current_organization,
          actor: current_user,
          secret_protection: params[:secret_protection],
          code_security: params[:code_security],
          dependabot: params[:dependabot],
          repository_ids: repository_ids,
          enforced: params[:enforced] || false
        )
      rescue ArgumentError => e
        render json: { error: e.message }, status: :unprocessable_entity
        return
      end

      if config.nil?
        render json: { error: "Failed to create configuration" }, status: :unprocessable_entity
        return
      end

      if config.errors.any?
        render json: { errors: config.errors.full_messages }, status: :unprocessable_entity
        return
      end

      render json: {}, status: :created
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
    #     - enforced: true/false
    #   - 404 Not Found if configuration doesn't exist
    sig { void }
    def show
      config = find_organization_security_configuration(params[:id].to_i)

      if config.nil?
        render_404
        return
      end

      # Get current Quick Setup states
      states = SecurityProductsEnablement::QuickSetupService.detect_configuration_drift(
        configuration_id: config.id
      )

      # Handle error case (e.g., config deleted between checks)
      if states[:error]
        render_404
        return
      end

      # Check if configuration is enforced
      enforced = config.enforced?(current_organization)

      render json: {
        secret_protection: states[:secret_protection],
        code_security: states[:code_security],
        dependabot: states[:dependabot],
        enforced: enforced
      }, status: :ok
    end

    # PATCH /organizations/:organization_id/settings/security_products/quick_setup_configurations/:id
    # Mock endpoint for updating Quick Setup configuration
    # This is used when the user saves changes from the edit dialog
    #
    # Parameters:
    #   - id: String - configuration ID
    #   - security_configuration: Hash of configuration settings (optional)
    #   - repository_ids: Array of repository IDs (optional)
    #
    # Returns:
    #   - 200 OK with mock success response
    sig { void }
    def update
      head :ok
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
    #     - total_repository_count: Total number of repositories matching the query
    sig { void }
    def repositories # rubocop:todo GitHub/UseRestfulActions
      search_query = params[:q].to_s
      configuration_id = params[:configuration_id].present? ? params[:configuration_id].to_i : nil

      # Validate configuration ownership if configuration_id is provided
      if configuration_id
        config = find_organization_security_configuration(configuration_id)

        if config.nil?
          render_404
          return
        end
      end

      result = serialized_repositories(
        organization: current_organization,
        user: current_user,
        user_session: user_session,
        cap_filter: cap_filter,
        search_query: search_query,
        current_page: 1,
        per_page: 500,
      )

      repositories = result[:repositories]

      # If configuration_id is provided, add configuration_applied field to each repository
      if configuration_id && repositories.any?
        applied_repo_ids = RepositorySecurityConfiguration
          .where(security_configuration_id: configuration_id, repository_id: repositories.map { |r| r[:id] })
          .applied
          .pluck(:repository_id)

        repositories.each { |r| r[:configuration_applied] = applied_repo_ids.include?(r[:id]) }
      end

      render json: {
        repositories: repositories,
        total_repository_count: result[:total_repository_count],
      }, status: :ok
    end

    private

    def check_feature_flag
      render_404 unless FeatureFlag.vexi.enabled?(:security_configs_quick_set_up, current_organization, default: false)
    end

    # Finds a security configuration that belongs to the current organization
    # Returns nil if the configuration doesn't exist or doesn't belong to the organization
    sig { params(id: Integer).returns(T.nilable(SecurityConfiguration)) }
    def find_organization_security_configuration(id)
      SecurityConfiguration.find_by(target: current_organization, id: id)
    end

    # Validates that all repository IDs belong to the current organization
    # Returns only the IDs that are valid (exist and belong to the org)
    sig { params(repository_ids: T::Array[Integer]).returns(T::Array[Integer]) }
    def validate_repository_ownership(repository_ids)
      return [] if repository_ids.empty?

      # Query only repositories that belong to the organization
      # This prevents unauthorized access to repositories from other organizations
      current_organization.repositories.where(id: repository_ids).pluck(:id)
    end
  end
end
