# typed: strict
# frozen_string_literal: true

class Businesses::CopilotSettingsController < Businesses::BusinessController
  include Site::MicrosoftAnalyticsDependency

  before_action :dotcom_required
  before_action :business_owner_required
  before_action :business_not_downgraded_to_free_plan_required
  before_action :check_business_is_not_trial_without_cfb_trial, except: [:index, :show_first_run_flow_cta]
  before_action :ensure_trial_business_is_dfd_trial_or_contains_cfb_trial, only: [:index]
  before_action :check_business_is_copilot_billable, only: [:update, :update_copilot_enablement, :update_individual_org_enablement, :update_bulk_org_enablement]
  before_action :check_organization_is_member_of_business, only: [:update_individual_org_enablement]
  before_action :check_organizations_are_members_of_business, only: [:update_bulk_org_enablement]
  before_action :check_business_is_copilot_billable_enterprise_ff, only: [:index] # TODO: Merge this into above when the :enterprise_copilot_licensing FF is removed
  before_action :check_valid_enablement_option, only: [:update_individual_org_enablement, :update_bulk_org_enablement]
  before_action :check_business_set_to_selected, only: [:update_bulk_org_enablement]
  before_action :mark_request_a_feature_notifications_as_read, only: [:index]
  before_action :parse_json_params, only: [:update_content_exclusion]

  before_action :enable_microsoft_analytics, only: [:index]
  before_action :add_microsoft_analytics_csp_exceptions, only: [:index]

  javascript_bundle :copilot

  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include ApplicationHelper
  include GitHub::Memoizer

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    ApplicationRecord::Billing,
    only: [:index, :search_orgs, :show_first_run_flow_cta, :download_seat_management_usage, :mcp_registry_index, :download_seat_management_activity]

  allow_verified_fetch only: [:update_copilot_enablement, :update_content_exclusion, :update_individual_org_enablement, :download_seat_management_usage, :update_bulk_org_enablement]

  PER_PAGE = 10
  BAD_SELECTION_ERROR_MESSAGE = "Select an option below to continue."
  BAD_ENABLEMENT_ERROR_MESSAGE = "You must allow for specific organizations to use GitHub Copilot to continue."
  COPILOT_ENABLED_FOR_BUSINESS = "GitHub Copilot has been enabled for your enterprise."
  COPILOT_DISABLED_FOR_BUSINESS = "GitHub Copilot has been disabled for your enterprise."
  COPILOT_ENABLED_FOR_SELECTED = "GitHub Copilot has been enabled for specified organizations."
  COPILOT_ENABLED_FOR_ALL = "GitHub Copilot has been enabled for all organizations."
  COPILOT_DISABLED_FOR_ALL_ORGS = "GitHub Copilot has been disabled for all organizations."
  COPILOT_PLAN_SCHEDULED_DOWNGRADE = "An organization has been scheduled to downgrade to Copilot Business. Download the report to see which seats are billed for the current billing cycle."
  COPILOT_POLICY_UPDATED = "GitHub Copilot policy has been updated."

  sig { void }
  def index
    render_index(organizations: paginated_orgs)
  end

  sig { void }
  def show_first_run_flow_cta # rubocop:todo GitHub/UseRestfulActions
    if this_business.trial?
      render "businesses/copilot_settings/trial_upgrade_cta", locals: {
        copilot_business: copilot_business,
      }
    else
      render "businesses/copilot_settings/first_run_flow_cta", locals: {
        copilot_business: copilot_business
      }
    end
  end

  sig { void }
  def update
    old_settings = copilot_business.copilot_business_settings

    use_new_policy_system = copilot_business.feature_flag_enabled?(:copilot_business_settings_refactor, default: false)
    # temp variable for accessing this later, TODO: remove when feature flag is cleaned up
    updated_policy_display_name = nil

    # overages policy is not in the new system, so update it separately
    if params[:copilot_overages]
      copilot_business.update_configuration!("overages", params[:copilot_overages], send_email: false)
    end

    if use_new_policy_system
      updated_policy_display_name = update_settings_candidate
    else
      update_settings_control
    end

    new_settings = copilot_business.copilot_business_settings

    if (new_settings[:editor_chat_setting] != old_settings[:editor_chat_setting]) && new_settings[:editor_chat_setting] != :EDITOR_CHAT_DISABLED
      Copilot::Instrumenter.instrument_clickwrap_saved(current_user, this_business, "pre-release")
    end

    unless old_settings == new_settings
      Copilot::Instrumenter.instrument_enterprise_settings_changed(
        current_user,
        this_business,
        old_settings: old_settings,
        new_settings: new_settings,
      )

      GitHub.logger.info(
        "Enterprise settings changed",
        "gh.business.id" => this_business.id,
        "gh.copilot.enterprise_settings.previous_settings" => old_settings,
        "gh.copilot.enterprise_settings.new_settings" => new_settings,
      )

      if use_new_policy_system
        if updated_policy_display_name.nil?
          flash[:notice] = COPILOT_POLICY_UPDATED
        else
          flash[:notice] = "#{updated_policy_display_name} setting updated."
        end
      else
        # TODO: Once we switch the params to match the keys we can simplify this
        _name, policy_config = Copilot::Policies::Config.policies.find do |_name, config|
          params.fetch(
            config.fetch(:business_controller_param, nil),
            nil
          )
        end

        if policy_config.present? && policy_config[:display_name]
          flash[:notice] = "#{policy_config[:display_name]} updated."
        else
          flash[:notice] = COPILOT_POLICY_UPDATED
        end

      end
    end


    if params[:return_to]
      safe_redirect_to(params[:return_to])
    else
      dest = if this_business.feature_flag_enabled?(:enterprise_copilot_policies_refresh, default: false)
        case get_tab
        when "policies"
          settings_copilot_enterprise_path(copilot_business)
        when "models"
          settings_copilot_models_enterprise_path(copilot_business)
        else
          settings_copilot_enterprise_path(copilot_business, tab: get_tab)
        end
      else
        settings_copilot_enterprise_path(copilot_business, tab: get_tab)
      end

      redirect_to dest
    end
  end

  # rubocop:todo GitHub/UseRestfulActions
  sig { void }
  def update_content_exclusion
    new_paths = params[:paths]
    config = Copilot::ContentExclusionConfiguration.for_business(this_business).first

    if config.present?
      GitHub.logger.info("Updating ContentExclusionConfiguration", "gh.business.id" => this_business.id, "gh.copilot_ignore_config.id" => config.id)
      config.update(document: new_paths, updated_by: current_user)
    else
      GitHub.logger.info("Creating ContentExclusionConfiguration", "gh.business.id" => this_business.id)
      config = Copilot::ContentExclusionConfiguration.create(
        resource: this_business,
        updated_by: current_user,
        resource_type: "Business",
        document: new_paths
      )
    end

    if new_paths.empty?
      GitHub.logger.info("Setting ContentExclusionConfiguration to blank for business", "gh.business.id" => this_business.id, "gh.user.id" => current_user.id)
    end

    if config.valid?
      payload = {
        message: "Successfully updated the excluded paths",
        lastEdited: {
          login: current_user&.display_login,
          time: config.updated_at,
          link: content_exclusions_audit_link
        }
      }

      render json: payload
    else
      render json: { message: config.errors.first.message }, status: :unprocessable_entity
    end
  end

  sig { void }
  def update_copilot_enablement # rubocop:todo GitHub/UseRestfulActions
    old_value = copilot_business.copilot_business_enablement_setting

    case params[:copilot_enabled]
    when "enabled"
      copilot_business.enable_copilot!
      flash[:notice] = COPILOT_ENABLED_FOR_BUSINESS
    when "disabled"
      copilot_business.disable_copilot!(current_user)
      copilot_business.unassign(
        Copilot::SeatAssignment.for_standalone_business(this_business).map(&:assignable) + Copilot::SeatAssignment.for_business_users(this_business).map(&:assignable),
        current_user
      )
      flash[:notice] = COPILOT_DISABLED_FOR_BUSINESS
    when "organizations_disabled"
      if this_business.feature_flag_enabled?(:enterprise_copilot_licensing, default: false) && !this_business.trial?
        copilot_business.disable_copilot_for_all_organizations!(current_user)
        flash[:notice] = COPILOT_DISABLED_FOR_ALL_ORGS
      else
        return render_index(organizations: paginated_orgs, error: BAD_SELECTION_ERROR_MESSAGE)
      end
    when "all_organizations"
      copilot_business.enable_copilot_for_all_organizations!(current_user)
      save_org_enablement_changes(ids: copilot_business.copilot_organizations.pluck(:id)) if params[:enablement]
      flash[:notice] = COPILOT_ENABLED_FOR_ALL
    when "selected_organizations"
      if !this_business.trial?
        copilot_business.enable_copilot_for_selected_organizations!([], current_user)
        flash[:notice] = COPILOT_ENABLED_FOR_SELECTED
      else
        return render_index(organizations: paginated_orgs, error: BAD_SELECTION_ERROR_MESSAGE)
      end
    else
      if params[:return_to]&.start_with?("/github-copilot/business_signup")
        flash[:error] = BAD_SELECTION_ERROR_MESSAGE
        return redirect_to copilot_business_signup_enterprise_seat_management_path(enterprise: copilot_business)
      else
        return render_index(organizations: paginated_orgs, error: BAD_SELECTION_ERROR_MESSAGE)
      end
    end

    new_value = copilot_business.copilot_business_enablement_setting

    Copilot::Instrumenter.instrument_clickwrap_saved(current_user, this_business)

    unless old_value == new_value
      if standalone_business?
        log_enablement_changed(::Copilot::Events::COPILOT_STANDALONE_ENABLEMENT_CHANGED, old_value, new_value)
        log_string = "Copilot Update Standlone Enterprise Enablement"
      else
        log_enablement_changed(::Copilot::Events::COPILOT_FOR_BUSINESS_ENTERPRISE_ORG_ENABLEMENT_CHANGED, old_value, new_value)
        log_string = "Copilot Update Org Enablement"
      end

      GitHub.logger.info(
        log_string,
        "gh.business.id" => this_business.id,
        "gh.copilot.org_enablement.old_value" => old_value,
        "gh.copilot.org_enablement.new_value" => new_value,
      )
    end


    if params[:return_to]
      # case: setting copilot business settings to allow for all organizations on the signup page
      safe_redirect_to(params[:return_to])
    else
      respond_to do |format|
        format.html_fragment do
          # case: setting copilot business settings to allow for specific organizations on the signup page
          head :ok
        end
        format.html do
          # case: updating copilot business settings on the settings page
          redirect_to settings_copilot_enterprise_path(copilot_business)
        end
      end
    end
  end

  sig { void }
  def update_individual_org_enablement # rubocop:todo GitHub/UseRestfulActions
    organization = Organization.find(params[:organization_id])
    copilot_organization = Copilot::Organization.new(organization)

    # This handles a special case which can happen in a couple of situations:
    #   * The enterprise was set to allow for all organizations prior to the introduction of mixed licensing, and never excplitly set a plan
    #   * An organization was added to / created directly on the enterprise
    #   * An organization converts from a trial to a paid plan
    is_simple_set_plan_request = copilot_organization.is_explicit_plan_confirmation?(params[:enablement])

    save_org_enablement_changes(ids: [params[:organization_id].to_i])

    if params[:reenable] == "true"
      flash[:notice] = "GitHub Copilot has been re-enabled for #{organization.display_login}."
    elsif params[:enablement] == "business" && copilot_organization.copilot_plan_enterprise?
      flash[:notice] = COPILOT_PLAN_SCHEDULED_DOWNGRADE
    elsif params[:enablement] == "business"
      if is_simple_set_plan_request
        flash[:notice] = "#{organization.display_login} plan set to Copilot Business."
      else
        flash[:notice] = "#{organization.display_login} has been granted access to Copilot Business. Organization administrators will receive an email with details and will be able to manage seats with the plan selected."
      end
    elsif params[:enablement] == "enterprise"
      if is_simple_set_plan_request
        flash[:notice] = "#{organization.display_login} plan set to Copilot Enterprise."
      else
        flash[:notice] = "#{organization.display_login} has been granted access to Copilot Enterprise. Organization administrators will receive an email with details and will be able to manage seats with the plan selected."
      end
    elsif params[:enablement] == "disable"
      flash[:notice] = "The access for #{organization.display_login} has been removed. Organization administrators will receive an email with details and will no longer be able to manage seats."
    end

    respond_to do |format|
      format.html_fragment do
        render(Copilot::OrgEnablement::OrgComponent.new(business: this_business, organization: organization, show_check: true), layout: false)
      end
      format.html do
        if pjax?
          render(Copilot::OrgEnablement::OrgComponent.new(business: this_business, organization: organization, show_check: true), layout: false)
        else
          redirect_to settings_copilot_enterprise_path(copilot_business)
        end
      end
    end
  end

  sig { void }
  def update_bulk_org_enablement # rubocop:todo GitHub/UseRestfulActions
    ids = params[:organizations].map(&:to_i)
    save_org_enablement_changes(ids: ids)
    organizations = params[:query].present? ? orgs_matching_query : paginated_orgs

    if params[:enablement] == "disable"
      flash[:notice] = "The access for #{ids.count} #{"organization".pluralize(ids.count)} has been removed. Organization administrators will receive an email with details and will no longer be able to manage seats."
    end

    respond_to do |format|
      format.html_fragment do
        render(Copilot::OrgEnablement::ListComponent.new(business: this_business, organizations: organizations), layout: false)
      end
      format.html do
        if pjax?
          render(Copilot::OrgEnablement::ListComponent.new(business: this_business, organizations: organizations), layout: false)
        else
          redirect_to settings_copilot_enterprise_path(copilot_business)
        end
      end
    end
  end

  sig { void }
  def update_swe_agent_repository_access
    # Checkboxes always send the same value so we need to toggle based on the current state
    if this_business.swe_agent_repository_access_enabled?
      this_business.disable_swe_agent_repository_access(actor: current_user, force: true)
    else
      this_business.enable_swe_agent_repository_access(actor: current_user)
    end

    dest = if this_business.feature_flag_enabled_or_raise?(:enterprise_copilot_policies_refresh) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      settings_copilot_enterprise_path(copilot_business)
    else
      settings_copilot_enterprise_path(copilot_business, tab: get_tab)
    end

    redirect_to dest
  end

  sig { void }
  def update_code_review_repository_access
    # Redirect unless the business has the feature enabled
    return render_404 unless copilot_business.feature_flag_enabled?(:copilot_code_review_policy, default: false)

    if this_business.code_review_repository_access_enabled?
      this_business.disable_code_review_repository_access(actor: current_user, force: true)
    else
      this_business.enable_code_review_repository_access(actor: current_user)
    end

    dest = if this_business.feature_flag_enabled?(:enterprise_copilot_policies_refresh, default: false)
      settings_copilot_enterprise_path(copilot_business)
    else
      settings_copilot_enterprise_path(copilot_business, tab: get_tab)
    end

    redirect_to dest
  end

  sig { void }
  def search_orgs # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html_fragment do
        render(Copilot::OrgEnablement::ListComponent.new(business: this_business, organizations: orgs_matching_query), layout: false)
      end
      format.html do
        if pjax?
          render(Copilot::OrgEnablement::ListComponent.new(business: this_business, organizations: orgs_matching_query), layout: false)
        else
          render_index(organizations: orgs_matching_query)
        end
      end
    end
  end

  sig { void }
  def download_seat_management_usage
    GitHub.dogstats.increment "copilot.access_management.generate_enterprise_seat_usage_csv"
    GitHub.logger.info("Generating Enterprise Seat Usage CSV", "gh.business.id" => this_business.id, "gh.user.id" => current_user&.id)
    send_data copilot_business.to_csv, filename: "#{this_business.slug.parameterize}-seat-usage-#{Time.current.to_i}.csv"
  end

  sig { void }
  def download_seat_management_activity
    GitHub.dogstats.increment "copilot.access_management.generate_enterprise_seat_activity_csv"
    GitHub.logger.info("Generating Enterprise Seat Activity CSV", "gh.business.id" => this_business.id, "gh.user.id" => current_user&.id)

    Copilot::ActivityReportJob.perform_later(
      entity_id: this_business.id,
      entity_type: "business",
      actor_id: current_user.id,
    )
    if this_business.feature_flag_enabled?(:enterprise_copilot_policies_refresh, default: false)
      render json: { ok: true }, status: 202
    else
      flash[:success] = "Your activity report is being generated. You will receive an email when it is ready to download."
      redirect_to settings_copilot_enterprise_path(copilot_business)
    end
  end

  sig { void }
  def mcp_registry_index
    registries = Copilot::McpAllowlist.for_business(this_business)
    respond_to do |format|
      format.json { render json: { registries: registries.map(&:to_json_hash) } }
      format.html { render json: { registries: registries.map(&:to_json_hash) } } # Assuming frontend will handle rendering
    end
  end

  sig { void }
  def mcp_registry_create_or_update
    registry_params = params.fetch(:copilot_mcp_allowlist, {})
    registry_url = params[:commit] == "Clear" ? nil : registry_params.fetch(:registry_url, nil)
    registry_access = registry_params[:registry_access]

    unless registry_access.present?
      flash[:error] = "Failed to #{params[:id].present? ? 'update' : 'create'} MCP registry due to missing registry access value."
      GitHub.logger.info("MCP registry access is a required parameter", "gh.business.id" => this_business.id, "gh.user.id" => current_user&.id)
      redirect_to settings_copilot_enterprise_path(copilot_business, tab: "policies")
      return
    end

    registry = if params[:id].present?
      Copilot::McpAllowlist.for_business(this_business).find(params[:id])
    else
      Copilot::McpAllowlist.new(entity: this_business, entity_type: "Business")
    end

    old_registry_access = registry.registry_access
    registry.registry_url = registry_url
    registry.registry_access = registry_access
    registry.updated_by = current_user

    if registry.save
      success_message = if params[:id].present? && params[:commit] == "Clear"
        "MCP Registry URL cleared successfully"
      else
        "MCP Registry URL #{params[:id].present? ? 'updated' : 'created'} successfully"
      end

      flash[:notice] = success_message
      redirect_to settings_copilot_enterprise_path(copilot_business, tab: "policies")
    else
      error_message = "Failed to #{params[:id].present? ? 'update' : 'create'} MCP Registry. #{registry.errors.full_messages.join(', ')}"
      flash[:error] = error_message
      redirect_to settings_copilot_enterprise_path(copilot_business, tab: "policies")
    end
  rescue ActiveRecord::RecordNotFound
    flash[:error] = "MCP registry not found"
    redirect_to settings_copilot_enterprise_path(copilot_business, tab: "policies")
  end

  sig { returns(T::Boolean) }
  def render_copilot_feedback_opt_in_settings?
    copilot_business.copilot_for_dotcom_enabled?
  end

  sig { returns(T::Boolean) }
  def render_copilot_beta_features_opt_in_settings?
    return true if copilot_business.copilot_for_dotcom_enabled?

    T.must(copilot_business.copilot_for_dotcom_enabled? &&
      copilot_business.copilot_organizations.any? { |org| org.copilot_enabled? && org.copilot_plan_enterprise? })
  end

  sig { returns(T::Boolean) }
  def render_copilot_swe_agent_settings?
    return false if GitHub.multi_tenant_enterprise? && !FeatureFlag.vexi.enabled?(:coding_agent_in_proxima, this_business, default: false)

    copilot_business.copilot_organizations.any? do |org|
      org.copilot_enabled? && org.swe_agent_eligible?(org, copilot_business)
    end
  end

  sig { returns(T::Boolean) }
  def render_copilot_code_review_settings?
    return false unless copilot_business.feature_flag_enabled?(:copilot_code_review_policy, default: false)

    copilot_business.copilot_organizations.any? do |org|
      org.copilot_enabled? && (org.copilot_plan_enterprise? || org.copilot_plan_business?)
    end
  end

  sig { returns(T::Boolean) }
  def render_copilot_code_review_beta_features_settings?
    return false unless copilot_business.feature_flag_enabled?(:copilot_code_review_policy, default: false)

    copilot_business.code_review_enabled?
  end


  private

  sig { returns(Copilot::Business) }
  def copilot_business # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @copilot_business ||= T.let(Copilot::Business.new(this_business), T.nilable(Copilot::Business))
  end

  sig { void }
  def check_business_set_to_selected
    # This can be removed when we remove the :enterprise_copilot_licensing FF as it's not a behaviour we want anymore
    # as we automatically change the setting to selected organizations when removing an invididual organization's access
    unless copilot_business.copilot_enabled_for_selected_organizations? || this_business.feature_flag_enabled?(:enterprise_copilot_licensing, default: false)
      render_index(organizations: paginated_orgs, error: BAD_ENABLEMENT_ERROR_MESSAGE)
    end
  end

  sig { void }
  def check_valid_enablement_option
    render_index(organizations: paginated_orgs, error: BAD_SELECTION_ERROR_MESSAGE) unless %w[enable disable business enterprise].include?(params[:enablement])
  end

  sig { void }
  def check_business_is_copilot_billable
    render_404 unless copilot_business.copilot_billable? || copilot_business.has_trial_organization? || this_business.digital_front_door?
  end

  # TODO: Remove this in favour of above once we remove the :enterprise_copilot_licensing FF
  sig { void }
  def check_business_is_copilot_billable_enterprise_ff
    check_business_is_copilot_billable if this_business.feature_flag_enabled?(:enterprise_copilot_licensing, default: false)
  end

  sig { void }
  def check_business_is_not_trial_without_cfb_trial
    return if this_business.digital_front_door?
    render_404 if this_business.trial? && !copilot_business.has_trial_organization?
  end

  sig { void }
  def ensure_trial_business_is_dfd_trial_or_contains_cfb_trial
    return unless this_business.trial?
    return if this_business.dfd_trial? && FeatureFlag.vexi.enabled?(:digital_front_door_getting_started, this_business, default: false)
    return if this_business.digital_front_door?
    render_404 unless copilot_business.has_trial_organization?
  end

  sig { void }
  def check_organization_is_member_of_business
    org_id = params[:organization_id].to_i
    render_404 unless this_business.organizations.where(id: org_id).exists?
  end

  sig { void }
  def check_organizations_are_members_of_business
    org_ids_from_params = params[:organizations].map(&:to_i)
    unique_org_ids = org_ids_from_params.uniq

    member_orgs_count = this_business.organizations.where(id: unique_org_ids).count
    render_404 unless member_orgs_count == unique_org_ids.length
  end

  sig { params(organizations: T::Array[::Organization], error: T.nilable(String)).void }
  def render_index(organizations:, error: nil)
    Copilot::Instrumenter.instrument_clickwrap_shown(current_user, this_business)

    if dfd_trial_business_without_cfb_trial?
      return render "businesses/copilot_settings/dfd_trial_without_copilot_business_trial"
    end

    if Copilot::Business.new(this_business).eligible_for_first_run_flow?
      render "businesses/copilot_settings/first_run_flow_cta"
      return
    end

    if standalone_business?
      render_standalone_index(error: error)
    else
      @cookie_consent_enabled = T.let(@cookie_consent_enabled, T.nilable(T::Boolean))
      @microsoft_analytics_enabled = T.let(@microsoft_analytics_enabled, T.nilable(T::Boolean))
      render "businesses/copilot_settings/index", locals: {
        copilot_business: copilot_business,
        organizations: organizations,
        title: this_business.feature_flag_enabled?(:enterprise_copilot_policies_refresh, default: false) ? "Copilot" : "GitHub Copilot",
        tab: get_tab || "access",
        error: error,
        copilot_custom_models: this_business.feature_flag_enabled?(:copilot_custom_models, default: false),
        features_for_data_retention: get_features_for_data_retention,
        feature_requests: feature_requests_count_by_organizations,
        render_copilot_feedback_opt_in_settings: render_copilot_feedback_opt_in_settings?,
        render_copilot_beta_features_opt_in_settings: render_copilot_beta_features_opt_in_settings?,
        render_copilot_swe_agent_settings: render_copilot_swe_agent_settings?,
        render_copilot_code_review_settings: render_copilot_code_review_settings?,
        render_copilot_code_review_beta_features_settings: render_copilot_code_review_beta_features_settings?,
        enable_msft_analytics: @cookie_consent_enabled && @microsoft_analytics_enabled,
        content_exclusions_partial_payload:
      }
    end
  end

  sig { params(error: T.nilable(String)).void }
  def render_standalone_index(error: nil)
    render "businesses/copilot_settings/standalone_index", locals: {
      copilot_business: copilot_business,
      title: "Copilot Business",
      error: error,
      features_for_data_retention: get_features_for_data_retention,
      tab: get_tab || "policies",
      content_exclusions_partial_payload:
    }
  end

  sig { returns(T.untyped) }
  def content_exclusions_partial_payload
    config = Copilot::ContentExclusionConfiguration.for_business(this_business).first

    # Keep types in sync with ui/packages/copilot-content-exclusion/partials/IgnoreForm.tsx#Payload
    {
      endpoint: update_settings_copilot_content_exclusion_enterprise_path(this_business),
      lastEdited: config&.updated_by ? { login: config.updated_by&.display_login, time: config.updated_at, link: content_exclusions_audit_link } : nil,
      document: config&.document,
    }
  end

  sig { returns(String) }
  def content_exclusions_audit_link
    query = Search::Queries::AuditLogQuery.stringify(["action:#{Copilot::Events::COPILOT_FOR_BUSINESS_CONTENT_EXCLUSION_CHANGED}"])
    settings_audit_log_enterprise_path(this_business, q: query)
  end

  sig { returns(T::Array[::Organization]) }
  def paginated_orgs
    page = params[:page] || 1

    if feature_requests_from_admins.any? || feature_requests_from_members_of_organizations.any?
      MemberFeatureRequest.sorted_organizations_by_features(
        organizations: this_business.organizations,
        admin_feature_requests: feature_requests_from_admins,
        member_feature_requests: feature_requests_from_members_of_organizations
      ).paginate(page: page, per_page: PER_PAGE).to_a
    else
      this_business.organizations.paginate(page: page, per_page: PER_PAGE).to_a
    end
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def feature_requests_count_by_organizations
    MemberFeatureRequest.feature_requests_count_by_organizations(
      admin_feature_requests: feature_requests_from_admins,
      member_feature_requests: feature_requests_from_members_of_organizations
    )
  end

  sig { returns(ActiveRecord::Relation) }
  memoize def feature_requests_from_admins
    MemberFeatureRequest.active_request_entities.where(billing_entity: this_business).includes(:request_entity, :requester)
  end

  sig { returns(ActiveRecord::Relation) }
  memoize def feature_requests_from_members_of_organizations
    MemberFeatureRequest.active_request_entities.where(billing_entity: this_business.organizations.pluck(:id)).includes(:request_entity, :requester)
  end

  sig { returns(T::Array[::Organization]) }
  def orgs_matching_query
    page = params[:page] || 1
    query = params[:query]
    this_business.organizations.where("`login` like ?", "%#{query}%").paginate(page: page, per_page: PER_PAGE).to_a
  end

  sig { params(ids: T::Array[Integer]).void }
  def save_org_enablement_changes(ids:)
    event = ::Copilot::Events::COPILOT_FOR_BUSINESS_ENTERPRISE_ORG_ENABLEMENT_CHANGED

    audit_payload = {
      actor: current_user,
      business: this_business,
    }

    enablement = params[:enablement]
    orgs = this_business.organizations.where(id: ids)
    orgs.each do |org|
      audit_payload[:org] = org
      audit_payload[:current_value] = enablement.to_s
      GitHub.instrument(event, audit_payload) unless %w(business enterprise).include?(enablement)
      org.plan_subscription&.synchronize_later
    end

    GitHub.dogstats.increment(event)

    case enablement
    when "enable"
      copilot_business.enable_copilot_for_selected_organizations!(ids, current_user)
    when "disable"
      # This block is triggered when an individual org is disabled from the UI (at the org row level)
      # update_org_enablement will handle the case when the org is disabled from the bulk action.
      # This option is only available when business is set to allow_for_selected_orgs
      copilot_business.disable_copilot_for_selected_organizations!(ids, current_user)
    when "business"
      if copilot_business.copilot_enabled_for_selected_organizations? || (this_business.feature_flag_enabled?(:enterprise_copilot_licensing, default: false) && copilot_business.copilot_disabled_for_all_organizations?)
        copilot_business.enable_copilot_for_selected_organizations!(ids, current_user)
      end

      orgs.each do |org|
        copilot_org = Copilot::Organization.new(org)

        if copilot_org.copilot_plan_enterprise?
          copilot_org.schedule_copilot_plan_downgrade!(current_user)
        else
          old_plan = copilot_org.copilot_plan(from_config: true)
          send_email = !copilot_org.is_explicit_plan_confirmation?(enablement)
          copilot_org.copilot_plan_business!(send_email)
          Copilot::Instrumenter.instrument_copilot_plan_changed(current_user, org, old_plan, "business")
        end
      end
    when "enterprise"
      if copilot_business.copilot_enabled_for_selected_organizations? || (this_business.feature_flag_enabled?(:enterprise_copilot_licensing, default: false) && copilot_business.copilot_disabled_for_all_organizations?)
        copilot_business.enable_copilot_for_selected_organizations!(ids, current_user)
      end

      orgs.each do |org|
        copilot_org = Copilot::Organization.new(org)
        old_plan = copilot_org.copilot_plan(from_config: true)
        send_email = !copilot_org.is_explicit_plan_confirmation?(enablement)
        copilot_org.copilot_plan_enterprise!(send_email)
        copilot_org.cancel_copilot_plan_downgrade!
        Copilot::Instrumenter.instrument_copilot_plan_changed(current_user, org, old_plan, "enterprise")
      end
    end

    if params[:reenable] == "true"
      orgs.each do |org|
        Copilot::Organization.new(org).seat_management_selected_teams_and_users!(keep_assignments: true)
      end
    end
  end

  sig { returns(T.nilable(String)) }
  def get_tab
    return if !copilot_business.copilot_billable? && !copilot_business.has_trial_organization? && !this_business.digital_front_door?

    params[:tab] || nil
  end

  sig { returns(T::Boolean) }
  def standalone_business?
    copilot_business.copilot_standalone?
  end

  sig { params(event: String, old_value: String, new_value: String).void }
  def log_enablement_changed(event, old_value, new_value)
    audit_payload = {
      actor: current_user,
      business: this_business,
      previous_value: old_value,
      current_value: new_value,
    }

    GitHub.dogstats.increment(event)

    GitHub.instrument(event, audit_payload)
  end

  sig { returns(String) }
  def get_features_for_data_retention
    return "" unless copilot_business.copilot_plan_business?

    features = []
    features << Copilot::CLI_UI_NAME
    features << Copilot::COPILOT_IN_DOTCOM if copilot_business.has_copilot_enterprise_access? && !standalone_business?
    features << Copilot::COPILOT_CHAT_IN_MOBILE
    features << Copilot::COPILOT_SWE_AGENT if (!GitHub.multi_tenant_enterprise? || FeatureFlag.vexi.enabled?(:coding_agent_in_proxima, this_business, default: false)) && !standalone_business?
    return "Enabling #{features.to_sentence} will collect additional data" if !features.empty?
    ""
  end

  sig { void }
  def mark_request_a_feature_notifications_as_read
    async_mark_threads_as_read(MemberFeatureRequest::Notification.where(entity: this_business, user: current_user))
  end

  sig { returns(T::Boolean) }
  def dfd_trial_business_without_cfb_trial?
    return false unless this_business.trial?
    return false unless this_business.dfd_trial?
    # This method can be deleted once the feature flag below is shipped
    return false if this_business.digital_front_door?
    !copilot_business.has_trial_organization?
  end

  sig { void }
  def update_settings_control
    case params[:copilot_public_code_suggestions]
    when "allowed"
      copilot_business.allow_public_code_suggestions!
      this_business.plan_subscription&.synchronize_later
    when "no_policy"
      copilot_business.no_public_code_suggestions_policy!
    when "blocked"
      copilot_business.block_public_code_suggestions!
    end

    if params[:copilot_ea_user_fallback_policy] && this_business.feature_flag_enabled?(:copilot_business_user_assignment, default: false)
      case params[:copilot_ea_user_fallback_policy]
      when "enabled"
        copilot_business.ea_user_fallback_policy_enabled!
      when "disabled"
        copilot_business.ea_user_fallback_policy_disabled!
      end
    end

    if params[:copilot_editor_chat_enabled]
      copilot_business.update_configuration!("chat_enabled", params[:copilot_editor_chat_enabled])
    end

    if params[:copilot_mobile_chat]
      copilot_business.update_configuration!("mobile_chat", params[:copilot_mobile_chat])
    end

    if this_business.feature_flag_enabled?(:copilot_custom_models, default: false)
      if params[:copilot_custom_models]
        copilot_business.update_configuration!("custom_models", params[:copilot_custom_models], send_email: false)
      end
    end

    if params[:cli]
      copilot_business.update_configuration!("cli", params[:cli])
    end

    if params[:desktop] && this_business.feature_flag_enabled?(:copilot_desktop, default: true)
      if this_business.feature_flag_enabled?(:copilot_desktop_business_refactor, default: false)
        Copilot::Policies::Desktop.update_business(copilot_business, params[:desktop])
      else
        copilot_business.update_configuration!("desktop", params[:desktop])
      end
    end

    if params[:bing_github_chat]
      copilot_business.update_configuration!("bing_github_chat", params[:bing_github_chat])
    end

    case params[:copilot_for_dotcom]
    when "enabled"
      copilot_business.copilot_for_dotcom_enabled!
    when "disabled"
      copilot_business.copilot_for_dotcom_disabled!
    when "no_policy"
      copilot_business.copilot_for_dotcom_no_policy!
    end

    case params[:copilot_user_feedback_opt_in]
    when "enabled"
      copilot_business.enable_user_feedback!
    when "disabled"
      copilot_business.disable_user_feedback!
    end

    if params[:copilot_extensions]
      copilot_business.update_configuration!("copilot_extensions", params[:copilot_extensions])
    end

    if params[:copilot_beta_features_opt_in]
      copilot_business.update_configuration!("beta_features_github_chat", params[:copilot_beta_features_opt_in], send_email: false)
    end

    if params[:copilot_telemetry_aggregation]
      copilot_business.update_configuration!("usage_telemetry_api", params[:copilot_telemetry_aggregation], send_email: false)
    end

    if params[:copilot_editor_preview_features]
      copilot_business.update_configuration!("editor_preview_features", params[:copilot_editor_preview_features])
    end

    if params[:copilot_agent_mode]
      copilot_business.update_configuration!("agent_mode", params[:copilot_agent_mode])
    end

    if params[:copilot_a_chat]
      copilot_business.update_configuration!("a_chat", params[:copilot_a_chat])
    end

    if params[:copilot_g_chat]
      copilot_business.update_configuration!("g_chat",  params[:copilot_g_chat])
    end

    if params[:copilot_g_tf] && this_business.feature_flag_enabled?(:copilot_g_tf, default: false)
      copilot_business.update_configuration!("g_tf",  params[:copilot_g_tf])
    end

    if params[:copilot_gtff] && this_business.feature_flag_enabled?(:copilot_gtff, default: false)
      copilot_business.update_configuration!("gtff",  params[:copilot_gtff])
    end

    if params[:copilot_a_f]
      copilot_business.update_configuration!("a_f",  params[:copilot_a_f])
    end

    if params[:copilot_afos] && this_business.feature_flag_enabled?(:copilot_afos, default: true)
      copilot_business.update_configuration!("afos",  params[:copilot_afos])
    end

    if params[:copilot_al] && this_business.feature_flag_enabled?(:copilot_al, default: true)
      copilot_business.update_configuration!("al",  params[:copilot_al])
    end

    if params[:copilot_o1]
      copilot_business.update_configuration!("o1", params[:copilot_o1])
    end

    if params[:copilot_mcp]
      copilot_business.update_configuration!("mcp", params[:copilot_mcp], send_email: false)
    end

    if params[:copilot_o3]
      copilot_business.update_configuration!("o3", params[:copilot_o3])
    end

    if params[:copilot_o_f]
      copilot_business.update_configuration!("o_f", params[:copilot_o3], send_email: false)
    end

    if params[:copilot_o_ff]
      copilot_business.update_configuration!("o_ff", params[:copilot_o_ff], send_email: false)
    end

    if params[:copilot_o_fm] && this_business.feature_flag_enabled?(:copilot_o_fm, default: true)
      copilot_business.update_configuration!("o_fm",  params[:copilot_o_fm])
    end

    if params[:copilot_o_t] && this_business.feature_flag_enabled?(:copilot_o_t, default: true)
      copilot_business.update_configuration!("o_t",  params[:copilot_o_t])
    end

    if params[:copilot_obmb] && this_business.feature_flag_enabled?(:copilot_obmb, default: false)
      copilot_business.update_configuration!("obmb",  params[:copilot_obmb])
    end

    if params[:copilot_obmw] && this_business.feature_flag_enabled?(:copilot_obmw, default: false)
      copilot_business.update_configuration!("obmw",  params[:copilot_obmw])
    end

    if params[:copilot_aofo] && this_business.feature_flag_enabled?(:copilot_aofo, default: false)
      copilot_business.update_configuration!("aofo",  params[:copilot_aofo])
    end

    if params[:copilot_ofo] && this_business.feature_flag_enabled?(:copilot_api_force_legacy_base_chat_model, default: true)
      copilot_business.update_configuration!("ofo",  params[:copilot_ofo])
    end

    if params[:copilot_grok_code] && this_business.feature_flag_enabled?(:copilot_grok_code, default: false)
      copilot_business.update_configuration!("grok_code",  params[:copilot_grok_code])
    end

    if params[:copilot_ofct] && this_business.feature_flag_enabled?(:copilot_ofct, default: true)
      copilot_business.update_configuration!("ofct",  params[:copilot_ofct])
    end

    if params[:copilot_swe_agent]
      copilot_business.update_configuration!("swe_agent", params[:copilot_swe_agent], send_email: false)
    end

    if params[:copilot_spark] && this_business.feature_flag_enabled?(:spark_access_copilot_policy, default: false)
      copilot_business.update_configuration!("spark", params[:copilot_spark], send_email: false)
    end

    if params[:copilot_insights] && this_business.feature_flag_enabled?(:copilot_insights, default: false)
      copilot_business.update_configuration!("insights", params[:copilot_insights], send_email: false)
    end

    if params[:copilot_code_review] && this_business.feature_flag_enabled?(:copilot_code_review_policy, default: false)
      copilot_business.update_configuration!("code_review", params[:copilot_code_review], send_email: false)
    end

    if params[:copilot_code_review_beta_features] && this_business.feature_flag_enabled?(:copilot_code_review_policy, default: false)
      copilot_business.update_configuration!("code_review_beta_features", params[:copilot_code_review_beta_features], send_email: false)
    end

    if this_business.enterprise_managed?
      case params[:copilot_workspace_for_emu]
      when "enabled"
        copilot_business.workspace_for_emu_enabled!
      when "disabled"
        copilot_business.workspace_for_emu_disabled!
      end
    end
  end

  sig { returns(T.nilable(String)) }
  def update_settings_candidate
    params.each do |key, value|
      policy_class = Copilot::Policies::BUSINESS_MUTABLE[key]
      if policy_class
        policy_class.update_business(copilot_business, value)

        # special case for disabling snippy
        if policy_class == Copilot::Policies::Snippy && value == "allowed"
          this_business.plan_subscription&.synchronize_later
        end

        # return the display name of the updated policy
        # this also ensures we only allow updating one policy at a time
        return policy_class.display_name
      end
    end

    nil
  end
end
