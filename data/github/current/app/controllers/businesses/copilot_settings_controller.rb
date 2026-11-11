# typed: strict
# frozen_string_literal: true

class Businesses::CopilotSettingsController < Businesses::BusinessController
  include Site::MicrosoftAnalyticsDependency

  before_action :dotcom_required
  before_action :business_owner_required, except: [:update, :update_swe_agent_repository_access, :update_code_review_repository_access, :mcp_registry_create_or_update]
  before_action :ai_controls_write_access_required, only: [:update, :update_swe_agent_repository_access, :update_code_review_repository_access, :mcp_registry_create_or_update]
  before_action :business_not_downgraded_to_free_plan_required
  before_action :ensure_trial_business_is_dfd_trial_or_contains_cfb_trial, only: [:index]
  before_action :check_business_is_copilot_billable, only: [:index, :update, :update_copilot_enablement, :update_individual_org_enablement, :update_bulk_org_enablement]
  before_action :check_organization_is_member_of_business, only: [:update_individual_org_enablement]
  before_action :check_organizations_are_members_of_business, only: [:update_bulk_org_enablement]
  before_action :check_valid_enablement_option, only: [:update_individual_org_enablement, :update_bulk_org_enablement]
  before_action :mark_request_a_feature_notifications_as_read, only: [:index]

  before_action :enable_microsoft_analytics, only: [:index]
  before_action :add_microsoft_analytics_csp_exceptions, only: [:index]

  javascript_bundle :copilot

  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include ApplicationHelper
  include GitHub::Memoizer
  include Businesses::CopilotShared

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
    only: [:index, :search_orgs, :show_first_run_flow_cta, :mcp_registry_index, :download_seat_management_activity]

  allow_verified_fetch only: [:update_copilot_enablement, :update_individual_org_enablement, :update_bulk_org_enablement]

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
  COPILOT_POLICY_MEMBER_REQUEST_ENABLED = "%{policy} is now enabled for everyone with a Copilot license in your enterprise."

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

    # overages policy is not in the new system, so update it separately
    if params[:copilot_overages]
      copilot_business.update_configuration!("overages", params[:copilot_overages], send_email: false)
    end

    # model registry policies are dynamic, so handle them separately
    if params[:model_registry_policy].present?
      params[:model_registry_policy].each do |model_key, policy_value|
        old_value = copilot_business.model_policy(model_key)
        next if old_value == policy_value

        case policy_value
        when "enabled"
          copilot_business.model_enabled!(model_key)
        when "disabled"
          copilot_business.model_disabled!(model_key)
        when "no_policy"
          copilot_business.model_no_policy!(model_key)
        end

        Copilot::Instrumenter.instrument_enterprise_settings_changed(
          current_user,
          this_business,
          old_settings: { model_key => old_value },
          new_settings: { model_key => policy_value },
        )
      end
    end

    updated_policy_display_name = update_settings

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
        "gh.user.id" => current_user.id,
        "gh.copilot.enterprise_settings.previous_settings" => old_settings,
        "gh.copilot.enterprise_settings.new_settings" => new_settings,
      )

      if updated_policy_display_name.nil?
        flash[:notice] = COPILOT_POLICY_UPDATED
      elsif is_member_request?
        flash[:success] = COPILOT_POLICY_MEMBER_REQUEST_ENABLED % { policy: updated_policy_display_name }
      else
        flash[:notice] = "#{updated_policy_display_name} setting updated."
      end
    end


    if params[:return_to]
      safe_redirect_to(params[:return_to])
    else
      policies_path = if helpers.show_ai_controls?(this_business)
        copilot_enterprise_ai_controls_enterprise_path(this_business)
      else
        settings_copilot_enterprise_path(copilot_business)
      end

      models_path = if helpers.show_ai_controls?(this_business)
        default_models_enterprise_ai_controls_enterprise_path(this_business)
      else
        settings_copilot_models_enterprise_path(copilot_business)
      end

      dest = case get_tab
      when "policies"
        policies_path
      when "models"
        models_path
      when "mcp"
        mcp_enterprise_ai_controls_enterprise_path(this_business)
      else
        settings_copilot_enterprise_path(copilot_business, tab: get_tab)
      end

      redirect_to dest
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
      if !this_business.trial?
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
          redirect_to copilot_settings_redirect_path
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
          redirect_to copilot_settings_redirect_path
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
          redirect_to copilot_settings_redirect_path
        end
      end
    end
  end

  sig { void }
  def update_swe_agent_repository_access # rubocop:todo GitHub/UseRestfulActions
    # Checkboxes always send the same value so we need to toggle based on the current state
    if this_business.swe_agent_repository_access_enabled?
      this_business.disable_swe_agent_repository_access(actor: current_user, force: true)
    else
      this_business.enable_swe_agent_repository_access(actor: current_user)
    end


    if params[:return_to]
      # case: setting copilot business settings to allow for all organizations on the signup page
      safe_redirect_to(params[:return_to])
    else
      dest = settings_copilot_enterprise_path(copilot_business)

      redirect_to dest
    end
  end

  sig { void }
  def update_code_review_repository_access # rubocop:todo GitHub/UseRestfulActions
    if this_business.code_review_repository_access_enabled?
      this_business.disable_code_review_repository_access(actor: current_user, force: true)
    else
      this_business.enable_code_review_repository_access(actor: current_user)
    end

    if params[:return_to]
      safe_redirect_to(params[:return_to])
    else
      dest = settings_copilot_enterprise_path(copilot_business)

      redirect_to dest
    end
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
  def download_seat_management_activity # rubocop:todo GitHub/UseRestfulActions
    GitHub.dogstats.increment "copilot.access_management.generate_enterprise_seat_activity_csv"
    GitHub.logger.info("Generating Enterprise Seat Activity CSV", "gh.business.id" => this_business.id, "gh.user.id" => current_user&.id)

    Copilot::ActivityReportJob.perform_later(
      entity_id: this_business.id,
      entity_type: "business",
      actor_id: current_user.id,
    )
    render json: { ok: true }, status: 202
  end

  sig { void }
  def mcp_registry_index # rubocop:todo GitHub/UseRestfulActions
    registries = Copilot::McpRegistry.for_business(this_business)
    respond_to do |format|
      format.json { render json: { registries: registries.map(&:to_json_hash) } }
      format.html { render json: { registries: registries.map(&:to_json_hash) } } # Assuming frontend will handle rendering
    end
  end

  sig { void }
  def mcp_registry_create_or_update # rubocop:todo GitHub/UseRestfulActions
    registry_params = params.fetch(:copilot_mcp_registry, {})
    registry_url = params[:commit] == "Clear" ? nil : registry_params.fetch(:registry_url, nil)
    registry_access = registry_params[:registry_access]
    registry_type = registry_params[:registry_type]

    old_settings = copilot_business.copilot_business_settings

    unless registry_access.present?
      flash[:error] = "Failed to #{params[:id].present? ? 'update' : 'create'} MCP registry due to missing registry access value."
      GitHub.logger.info("MCP registry access is a required parameter", "gh.business.id" => this_business.id, "gh.user.id" => current_user&.id)
      redirect_to mcp_registry_redirect_path
      return
    end

    registry = if params[:id].present?
      Copilot::McpRegistry.for_business(this_business).find(params[:id])
    else
      Copilot::McpRegistry.new(entity: this_business, entity_type: "Business")
    end

    old_registry_access = registry.registry_access
    registry.registry_url = registry_url
    registry.registry_access = registry_access
    registry.registry_type = registry_type if registry_type.present?
    registry.updated_by = current_user

    if registry.save
      success_message = if params[:id].present? && params[:commit] == "Clear"
        "MCP Registry URL cleared successfully"
      else
        "MCP Registry URL #{params[:id].present? ? 'updated' : 'created'} successfully"
      end

      new_settings = copilot_business.copilot_business_settings
      unless old_settings == new_settings
        Copilot::Instrumenter.instrument_enterprise_settings_changed(
          current_user,
          this_business,
          old_settings: old_settings,
          new_settings: new_settings
        )
      end

      GitHub.logger.info(
        "Enterprise MCP registry settings changed",
        "gh.business.id" => this_business.id,
        "gh.user.id" => current_user.id,
        "gh.copilot.enterprise.previous_settings" => old_settings,
        "gh.copilot.enterprise.new_settings" => new_settings
      )

      flash[:notice] = success_message
      redirect_to mcp_registry_redirect_path
    else
      error_message = "Failed to #{params[:id].present? ? 'update' : 'create'} MCP Registry. #{registry.errors.full_messages.join(', ')}"
      flash[:error] = error_message
      redirect_to mcp_registry_redirect_path
    end
  rescue ActiveRecord::RecordNotFound
    flash[:error] = "MCP registry not found"
    redirect_to mcp_registry_redirect_path
  end

  private

  sig { returns(String) }
  def mcp_registry_redirect_path
    if helpers.show_ai_controls?(this_business)
      mcp_enterprise_ai_controls_enterprise_path(this_business)
    else
      settings_copilot_enterprise_path(copilot_business, tab: "policies")
    end
  end

  sig { returns(String) }
  def copilot_settings_redirect_path
    if helpers.show_ai_controls?(this_business)
      copilot_enterprise_ai_controls_enterprise_path(this_business)
    else
      settings_copilot_enterprise_path(copilot_business)
    end
  end

  sig { void }
  def check_valid_enablement_option
    render_index(organizations: paginated_orgs, error: BAD_SELECTION_ERROR_MESSAGE) unless %w[enable disable business enterprise].include?(params[:enablement])
  end

  sig { void }
  def check_business_is_copilot_billable
    render_404 unless is_copilot_billable? || copilot_business.has_trial_organization? || this_business.digital_front_door?
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

    render_trial_entry_flow
    return if performed?

    if standalone_business?
      render_standalone_index(error: error)
    else
      if this_business.feature_flag_enabled?(:enterprise_ai_controls_deprecate_policies_page, default: false)
        redirect_to copilot_settings_redirect_path
      else
        @cookie_consent_enabled = T.let(@cookie_consent_enabled, T.nilable(T::Boolean))
        @microsoft_analytics_enabled = T.let(@microsoft_analytics_enabled, T.nilable(T::Boolean))
        render "businesses/copilot_settings/index", locals: {
          copilot_business: copilot_business,
          organizations: organizations,
          title: "Copilot",
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
          render_cli_direct_org_billing_settings: render_cli_direct_org_billing_settings?,
          render_ccr_direct_org_billing_settings: render_ccr_direct_org_billing_settings?,
          render_cca_direct_org_billing_settings: render_cca_direct_org_billing_settings?,
          enable_msft_analytics: @cookie_consent_enabled && @microsoft_analytics_enabled,
          content_exclusions_partial_payload:,
          show_ai_controls_notice: helpers.show_ai_controls?(this_business),
          can_write: this_business&.actor_can_write_enterprise_ai_controls?(current_user) || false,
          available_models: available_models_for_business,
          is_copilot_billable: is_copilot_billable?,
        }
      end
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
      content_exclusions_partial_payload:,
      can_write: this_business&.actor_can_write_enterprise_ai_controls?(current_user) || false,
      available_models: available_models_for_business,
    }
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
      if copilot_business.copilot_enabled_for_selected_organizations? || copilot_business.copilot_disabled_for_all_organizations?
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
      if copilot_business.copilot_enabled_for_selected_organizations? || copilot_business.copilot_disabled_for_all_organizations?
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
    return if !is_copilot_billable? && !copilot_business.has_trial_organization? && !this_business.digital_front_door?

    params[:tab] || nil
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

  sig { void }
  def mark_request_a_feature_notifications_as_read
    async_mark_threads_as_read(MemberFeatureRequest::Notification.where(entity: this_business, user: current_user))
  end

  sig { returns(T.nilable(String)) }
  def update_settings
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

  sig { returns(T::Boolean) }
  def is_member_request?
    params[:is_member_request] == "true"
  end

  sig { void }
  def ai_controls_write_access_required
    if helpers.show_ai_controls?(this_business) && FeatureFlag.vexi.enabled?(:enterprise_ai_controls_fine_grained_permissions, this_business, default: false)
      # Use fine-grained AI controls permissions
      render_404 unless this_business&.actor_can_write_enterprise_ai_controls?(current_user)
    else
      # Fall back to business owner requirement
      business_owner_required
    end
  end

  sig { returns(T::Boolean) }
  memoize def is_copilot_billable?
    copilot_business.copilot_billable?
  end

  sig { void }
  def render_trial_entry_flow
    if helpers.show_ai_controls?(this_business) && this_business.feature_flag_enabled?(:enterprise_ai_controls_deprecate_policies_page, default: false) && !standalone_business?
      # Trial flow is rendered because the controllers for this path handle the entry trial flow with the same before action `handle_ai_controls_trial_entry_flow`.
      redirect_to copilot_settings_redirect_path
    else
      # Fall back to original behaviour for backward compatability
      if dfd_trial_business_without_cfb_trial?
        return render "businesses/copilot_settings/dfd_trial_without_copilot_business_trial"
      end

      if Copilot::Business.new(this_business).eligible_for_first_run_flow?
        render "businesses/copilot_settings/first_run_flow_cta"
      end
    end
  end
end
