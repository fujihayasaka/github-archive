# typed: true
# frozen_string_literal: true

class Repos::SecurityAndAnalysis::SettingsController < AbstractRepositoryController
  map_to_service :advanced_security_billing, only: [:update_ghas_settings] # rubocop:todo GitHub/MapToService

  javascript_bundle :settings

  include GitHub::Memoizer
  include ControllerMethods::SecurityAnalysisSettings
  include SecurityAnalysisSettingsHelper
  include SecretScanningCustomPatternsHelper
  include SecretScanning::Features::FeatureFlagHelper
  include SharedSecurityConfigurationsDependency

  skip_before_action :privacy_check,
    only: [
      :security_analysis,
      :update_ghas_settings,
      :update_security_products_settings,
      :automatic_dependency_submission_options
    ]

  track_availability_slo "ui-request", only: [:update_ghas_settings]
  track_latency_slo "p50-ui-request", 500, only: [:update_ghas_settings]
  track_latency_slo "p99-ui-request", 2000, only: [:update_ghas_settings]

  before_action :manage_security_products_permission_required,
    only: [
      :security_analysis,
      :update_ghas_settings,
      :update_security_products_settings,
      :automatic_dependency_submission_options
    ]
  before_action :writable_repository_required, except: [:security_analysis, :automatic_dependency_submission_options]
  before_action :writable_repository_required, only: [:security_analysis, :automatic_dependency_submission_options], unless: :repository_archived_and_secret_scanning_present?
  before_action :allowed_repo_criteria, only: [:update_ghas_settings]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::SecurityProductsEnablement,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Iam,
    ApplicationRecord::Billing,
    ApplicationRecord::Memex,
    ApplicationRecord::Notify,
    ApplicationRecord::Permissions,
    only: [:security_analysis, :automatic_dependency_submission_options]

  depends_on_clusters \
    ApplicationRecord::Copilot,
    ApplicationRecord::SecurityOverviewAnalytics,
    optional: true,
    only: [:security_analysis, :automatic_dependency_submission_options]

  sig { returns(String) }
  def self.react_bundle_name
    "security-products-enablement"
  end

  def security_analysis # rubocop:todo GitHub/UseRestfulActions
    @selected_link = :security_analysis

    if current_repository.feature_flag_enabled?(:repository_security_settings, default: false)
      # Repo name, owner name, security configuration, repoSecurityConfig state, enablement value for each security product (this will be easier after consistent persistence)
      render_react_app(
        payload: default_payload,
        title: "Code security",
        page_data: {
          selected_link: @selected_link,
        },
        layout: "repository_settings",
      )
    else
      manager = settings_manager
      manager.data.has_mixed_restrictions = manager.has_mixed_restrictions?

      render "edit_repositories/pages/security_analysis", locals: {
        data:,
        manager:,
        current_repository:
      }
    end
  end

  # This action is used to enable/disable GHAS (in bundled mode) or Code
  # Security / Secret Protection (in split mode).
  def update_ghas_settings # rubocop:todo GitHub/UseRestfulActions
    sku = GitHub::Turboghas::SKU.from_param(params[:sku])

    case sku
    when GitHub::Turboghas::SKU::Bundled
      return render_404 if advanced_security_blocked_by_policy?
      return render_404 unless advanced_security_configurable?
      return render_blocked_by_update_already_in_progress if blocked_settings.advanced_security?
    when GitHub::Turboghas::SKU::CodeSecurity
      return render_404 unless code_security_configurable?
      return render_blocked_by_update_already_in_progress if blocked_settings.code_scanning?
    when GitHub::Turboghas::SKU::SecretSecurity
      return render_404 unless secret_protection_configurable?
      return render_blocked_by_update_already_in_progress if blocked_settings.secret_scanning?
    end
    enablement_value = params.fetch(:advanced_security_enabled, "0")

    enabled = case sku
    when GitHub::Turboghas::SKU::Bundled
      current_repository.advanced_security_enabled?
    when GitHub::Turboghas::SKU::CodeSecurity
      CodeSecurity::Features::AdvancedSecurityHelper.code_security_enabled?(repository: current_repository)
    end

    # Abort if enabling the SKU would push the license over its seat limit.
    # The UI for this should be disabled in this case, but we check here too
    # to prevent against accidentally going the license limit by viewing an
    # outdated page, or to a lesser extent by deliberate manipulation of the
    # form submission.
    license = current_repository.owner.advanced_security_license_for_sku(sku:)
    if current_repository.enforce_advanced_security_committers_limits? &&
      enablement_value == "1" && !enabled && license.enabling_repo_exceeds_seat_allowance?(current_repository)

      repo_owner = current_repository.owner
      preamble = if repo_owner.is_a?(Organization) && repo_owner.advanced_security_billable_entity?
        "the parent organization"
      else
        "the parent enterprise"
      end

      seats_needed = license.seat_usage_increase_if_enabled_for_repo(current_repository)
      return redirect_to :back, flash: { error: "#{ sku.title } could not be enabled because #{preamble} " +
        advanced_security_blocked_by_seat_count_message(target: current_repository, seats_needed:) }
    end

    if enablement_value == "0" && (sku == GitHub::Turboghas::SKU::CodeSecurity || sku == GitHub::Turboghas::SKU::Bundled)
      GitHub::Turboscan.set_advanced_setup_requested(repository_id: current_repository.id, advanced_setup_requested: false)
    end

    enablement_param = case sku
    when GitHub::Turboghas::SKU::Bundled
      :advanced_security_enabled
    when GitHub::Turboghas::SKU::CodeSecurity
      :code_security_enabled
    when GitHub::Turboghas::SKU::SecretSecurity
      :token_scanning_enabled
    end
    result = SecurityProduct::ServiceManager.new(current_repository).toggle_services_with_form_inputs(T.must(current_user), params: { enablement_param => enablement_value })

    if result.error?
      flash[:error] = "Could not update Repository settings"
      redirect_to :back
    else
      flash[:notice] = "Repository settings saved."
      redirect_to :back
    end
  end

  # This action is for disabling and enabling security products. It's more granular than
  # update_ghas_settings, since it deals with individual features.
  def update_security_products_settings # rubocop:todo GitHub/UseRestfulActions
    return render_404 if params[:dependency_graph_enabled].present? && dependency_graph_blocked_by_policy?
    return render_404 if params[:vulnerability_alerts_enabled].present? && dependabot_alerts_blocked_by_policy?
    return render_404 if params[:vulnerability_updates_enabled].present? && dependabot_updates_blocked_by_policy?
    return render_404 if params[:vulnerability_updates_grouping_enabled].present? && dependabot_updates_blocked_by_policy?
    return render_404 if params[:dependabot_on_actions_enabled].present? && dependabot_updates_blocked_by_policy?
    return render_404 if params[:dependabot_self_hosted_enabled].present? && dependabot_updates_blocked_by_policy?
    return render_404 if params[:dependabot_autofix_enabled].present? && dependabot_updates_blocked_by_policy?
    return render_404 if params[:token_scanning_enabled].present? && secret_scanning_blocked_by_policy?
    return render_404 if params[:token_scanning_push_protection_enabled].present? && push_protection_blocked_by_policy?
    return render_404 if params[:token_scanning_generic_secrets_enabled].present? && generic_secrets_blocked_by_policy?
    return render_blocked_by_update_already_in_progress if params.key?(:token_scanning_enabled) && blocked_settings.secret_scanning?
    return render_blocked_by_update_already_in_progress if params.key?(:token_scanning_push_protection_enabled) && blocked_settings.push_protection?

    package_selection_error = T.let(false, T::Boolean)

    # Ideally this would be inside a transaction however several enable and disable methods queue jobs
    # or check things with Actions.
    # It is an availability risk to leave a transaction open while you query an external service over HTTP.
    # If it fails part way then users will just have to try applying the configuration again and we should ensure
    # that operation is idempotent.
    security_params = params.except(:advanced_security_enabled)
    service_toggle_response = SecurityProduct::ServiceManager.new(current_repository).toggle_services_with_form_inputs(
      T.must(current_user),
      params: security_params,
      use_human_readable_error: true
    )

    if params[:code_security_enabled] == "0"
      GitHub::Turboscan.set_advanced_setup_requested(repository_id: current_repository.id, advanced_setup_requested: false)
    end

    if params[:used_by_package_id]
      if package_id_belongs_to_repo?(params[:used_by_package_id])
        current_repository.set_used_by_package_id(actor: current_user, package_id: params[:used_by_package_id])
      else
        package_selection_error = true
      end
    end

    if package_selection_error
      if T.must(request).xhr?
        head :unprocessable_entity
      else
        flash[:error] = "Package selection could not be set."
        redirect_to :back
      end
    # Some services (e.g. Dependency Graph) add error details to `current_repository.errors`
    # as a side-effect in their `can_enable?` method.
    #
    # Others (e.g. Code Security), rely on error info being returned from the method call.
    #
    # We should really standardize on one way of doing this! In the meantime, since
    # `handle_request_response` checks current_repository.errors, we don't want to break
    # that behaviour by handling _those_ errors here, so only consider errors returned
    # in this condition if there aren't also any on the repository.
    elsif service_toggle_response.error? && current_repository.errors.none?
      flash[:error] = "Repository settings could not be saved: #{service_toggle_response.error}"
      redirect_to :back
    else
      handle_request_response
    end
  end

  def automatic_dependency_submission_options # rubocop:todo GitHub/UseRestfulActions
    ads_service = SecurityProduct::DependencyGraphAutosubmitAction.new(current_repository)

    service_enabled = ads_service.enabled?
    labeled_runners_enabled = ads_service.labeled_runners_enabled?
    labeled_runners_available = ads_service.labeled_runners_available?

    render partial: "edit_repositories/pages/code_security/automatic_dependency_submission_menu", locals: {
      current_repository:,
      service_enabled:,
      labeled_runners_enabled:,
      labeled_runners_available:,
    }
  end

  private

  def data
    create_toggled_settings_model(blocked_settings: blocked_settings)
  end

  def settings_manager
    SecurityProductsEnablement::RepositorySettings::Manager.new(
      repository: current_repository,
      actor: T.must(current_user),
      data:,
      cursor: SecretScanningCustomPatternsHelper::get_custom_patterns_cursor(params),
      custom_patterns_query: params[:query],
    )
  end

  def public_scanning # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @public_scanning ||= SecretScanning::Features::Repo::PublicScanning.new(current_repository)
  end

  def token_scanning # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @token_scanning ||= SecretScanning::Features::Repo::TokenScanning.new(current_repository)
  end

  memoize def blocked_settings
    BlockedSettings.new(current_repository.owner)
  end

  def repository_archived_and_secret_scanning_present?
    return false unless current_repository.archived?

    public_scanning.feature_available? || token_scanning.feature_available?
  end

  # Test if a package_id belongs to this repository. This is used to prevent someone from
  # injecting a package ID which doesn't belong to them into the Used By package setting.
  #
  # Returns bool
  def package_id_belongs_to_repo?(package_id)
    packages = Platform::Loaders::Dependencies.load_packages({
      package_filter: {
        repository_id: current_repository.id,
        preview: current_repository.dependency_graph_preview?,
      },
    }).sync
    return false unless packages.ok?

    package_ids = packages.value!.map { |package| package.id.to_s }
    package_ids.include?(package_id)
  end

  def used_by_selection_view_packages # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @used_by_selection_view_packages ||= Platform::Loaders::Dependencies.load_packages({
      package_filter: {
        repository_id: current_repository.id,
        first: 100,
        preview: current_repository.dependency_graph_preview?,
      },
      dependents_filter: { type: :repository },
      include_dependent_counts: true,
    }).sync.value { [] }
  end

  def render_blocked_by_update_already_in_progress
    flash[:error] = blocked_settings.repo_message
    redirect_to :back
  end

  def handle_request_response(redirect_to = :back)
    if T.must(request).xhr?
      # TODO: Should handle with live updates.
      respond_to do |format|
        format.html do
          render Repositories::UnderlineNavComponent.new(
            repository: current_repository,
            selected_link: :repo_settings,
            display_variant: :padded,
            user_can_write_wiki: current_user_can_write_wiki?
          ), layout: false
        end
      end
    elsif current_repository.errors.any?
      flash[:error] = "Error saving your changes: #{current_repository.errors.full_messages.to_sentence}"
      redirect_to redirect_to
    else
      flash[:notice] = "Repository settings saved." unless flash[:error].present? || flash[:notice].present?
      redirect_to redirect_to
    end
  end

  sig { returns(Hash) }
  def default_payload
    payload = shared_default_payload
    # Missing repo level enablement data (security product enablement status)
    payload.merge({
      renderContext: "repository",
      owner: current_repository.owner.display_login,
      repository: current_repository.name,
      repoSettingsAvailable: repository_security_settings?,
      repositorySecurityConfigurationState: repository_security_configuration_state,
      securityConfiguration: serialized_security_configuration,
      restriction: settings_manager.restriction
    })
  end

  sig { returns(T::Boolean) }
  def repository_security_settings?
    current_repository.feature_flag_enabled?(:repository_security_settings, default: false) || false
  end

  def repository_security_configuration
    RepositorySecurityConfiguration.find_by(repository_id: current_repository.id)
  end

  sig { returns T.nilable(String) }
  def repository_security_configuration_state
    repository_security_configuration.state if repository_security_configuration
  end

  sig { returns(SecurityProductsEnablement::SecurityConfigurationSerializer) }
  memoize def security_configuration_serializer
    SecurityProductsEnablement::SecurityConfigurationSerializer.new(current_repository.owner)
  end

  def security_configuration
    SecurityConfiguration.find_by(id: repository_security_configuration.security_configuration_id) if repository_security_configuration
  end

  def serialized_security_configuration
    security_configuration_serializer.serialize(security_configuration, details: true)
  end
end
