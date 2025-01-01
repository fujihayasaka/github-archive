# typed: strict
# frozen_string_literal: true

class Businesses::CopilotSettingsController < Businesses::BusinessController
  include Site::MicrosoftAnalyticsDependency

  before_action :dotcom_required
  before_action :business_owner_required
  before_action :business_not_downgraded_to_free_plan_required
  before_action :check_business_is_not_trial_without_cfb_trial, except: [:show_first_run_flow_cta]
  before_action :check_business_is_copilot_billable, only: [:update, :update_copilot_enablement, :update_individual_org_enablement, :update_bulk_org_enablement]
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
    only: [:index, :search_orgs, :show_first_run_flow_cta, :download_seat_management_usage]

  allow_verified_fetch only: [:update_copilot_enablement, :update_content_exclusion, :update_individual_org_enablement, :download_seat_management_usage, :update_bulk_org_enablement]

  PER_PAGE = 10
  BAD_SELECTION_ERROR_MESSAGE = "Select an option below to continue."
  BAD_ENABLEMENT_ERROR_MESSAGE = "You must allow for specific organizations to use GitHub Copilot to continue."
  COPILOT_ENABLED_FOR_BUSINESS = "GitHub Copilot has been enabled for your enterprise."
  COPILOT_DISABLED_FOR_BUSINESS = "GitHub Copilot has been disabled for your enterprise."
  COPILOT_ENABLED_FOR_SELECTED = "GitHub Copilot has been enabled for specified organizations."
  COPILOT_ENABLED_FOR_ALL = "GitHub Copilot has been enabled for all organizations."
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

    case params[:copilot_public_code_suggestions]
    when "allowed"
      copilot_business.allow_public_code_suggestions!
      this_business.plan_subscription&.synchronize_later
    when "no_policy"
      copilot_business.no_public_code_suggestions_policy!
    when "blocked"
      copilot_business.block_public_code_suggestions!
    end

    if params[:copilot_editor_chat_enabled]
      copilot_business.update_configuration!("chat_enabled", params[:copilot_editor_chat_enabled])
    end

    if params[:copilot_mobile_chat]
      copilot_business.update_configuration!("mobile_chat", params[:copilot_mobile_chat])
    end

    if this_business.feature_enabled?(:copilot_custom_models)
      if params[:copilot_custom_models]
        copilot_business.update_configuration!("custom_models", params[:copilot_custom_models], send_email: false)
      end
    end

    if params[:cli]
      copilot_business.update_configuration!("cli", params[:cli])
    end

    if params[:desktop] && this_business.feature_enabled?(:copilot_desktop)
      copilot_business.update_configuration!("desktop", params[:desktop])
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

    if params[:copilot_a_chat]
      copilot_business.update_configuration!("a_chat", params[:copilot_a_chat])
    end

    if params[:copilot_g_chat]
      copilot_business.update_configuration!("g_chat",  params[:copilot_g_chat])
    end

    if params[:copilot_g_tf] && this_business.feature_enabled?(:copilot_g_tf)
      copilot_business.update_configuration!("g_tf",  params[:copilot_g_tf])
    end

    if params[:copilot_gtff] && this_business.feature_enabled?(:copilot_gtff)
      copilot_business.update_configuration!("gtff",  params[:copilot_gtff])
    end

    if params[:copilot_a_f]
      copilot_business.update_configuration!("a_f",  params[:copilot_a_f])
    end

    if params[:copilot_afos] && this_business.feature_enabled?(:copilot_afos)
      copilot_business.update_configuration!("afos",  params[:copilot_afos])
    end

    if params[:copilot_al] && this_business.feature_enabled?(:copilot_al)
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

    if params[:copilot_o_fm] && this_business.feature_enabled?(:copilot_o_fm)
      copilot_business.update_configuration!("o_fm",  params[:copilot_o_fm])
    end

    if params[:copilot_o_t] && this_business.feature_enabled?(:copilot_o_t)
      copilot_business.update_configuration!("o_t",  params[:copilot_o_t])
    end

    if params[:copilot_ofo] && this_business.feature_enabled?(:copilot_api_force_legacy_base_chat_model)
      copilot_business.update_configuration!("ofo",  params[:copilot_ofo])
    end

    if params[:copilot_overages]
      copilot_business.update_configuration!("overages", params[:copilot_overages], send_email: false)
    end

    if params[:copilot_swe_agent]
      copilot_business.update_configuration!("swe_agent", params[:copilot_swe_agent], send_email: false)
    end

    if this_business.enterprise_managed?
      case params[:copilot_workspace_for_emu]
      when "enabled"
        copilot_business.workspace_for_emu_enabled!
      when "disabled"
        copilot_business.workspace_for_emu_disabled!
      end
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


    if params[:return_to]
      safe_redirect_to(params[:return_to])
    else
      dest = if this_business.feature_enabled?(:enterprise_copilot_policies_refresh)
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
    when "all_organizations"
      copilot_business.enable_copilot_for_all_organizations!(current_user)
      save_org_enablement_changes(ids: copilot_business.copilot_organizations.pluck(:id)) if params[:enablement]
      flash[:notice] = COPILOT_ENABLED_FOR_ALL
    when "selected_organizations"
      copilot_business.enable_copilot_for_selected_organizations!([], current_user)
      flash[:notice] = COPILOT_ENABLED_FOR_SELECTED
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
    return false if GitHub.multi_tenant_enterprise?

    # Ensure the business actually has any enterprise-licensed organizations
    copilot_business.copilot_organizations.any? do |org|
      org.copilot_enabled? && org.copilot_plan_enterprise?
    end
  end

  private

  sig { returns(Copilot::Business) }
  def copilot_business # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @copilot_business ||= T.let(Copilot::Business.new(this_business), T.nilable(Copilot::Business))
  end

  sig { void }
  def check_business_set_to_selected
    render_index(organizations: paginated_orgs, error: BAD_ENABLEMENT_ERROR_MESSAGE) unless copilot_business.copilot_enabled_for_selected_organizations?
  end

  sig { void }
  def check_valid_enablement_option
    render_index(organizations: paginated_orgs, error: BAD_SELECTION_ERROR_MESSAGE) unless %w[enable disable business enterprise].include?(params[:enablement])
  end

  sig { void }
  def check_business_is_copilot_billable
    render_404 unless copilot_business.copilot_billable? || copilot_business.has_trial_organization?
  end

  # TODO: Remove this in favour of above once we remove the :enterprise_copilot_licensing FF
  sig { void }
  def check_business_is_copilot_billable_enterprise_ff
    check_business_is_copilot_billable if this_business.feature_enabled?(:enterprise_copilot_licensing)
  end

  sig { void }
  def check_business_is_not_trial_without_cfb_trial
    render_404 if this_business.trial? && !copilot_business.has_trial_organization?
  end

  sig { params(organizations: T::Array[::Organization], error: T.nilable(String)).void }
  def render_index(organizations:, error: nil)
    Copilot::Instrumenter.instrument_clickwrap_shown(current_user, this_business)

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
        title: this_business.feature_enabled?(:enterprise_copilot_policies_refresh) ? "Copilot" : "GitHub Copilot",
        tab: get_tab || "access",
        error: error,
        copilot_custom_models: this_business.feature_enabled?(:copilot_custom_models),
        features_for_data_retention: get_features_for_data_retention,
        feature_requests: feature_requests_count_by_organizations,
        render_copilot_feedback_opt_in_settings: render_copilot_feedback_opt_in_settings?,
        render_copilot_beta_features_opt_in_settings: render_copilot_beta_features_opt_in_settings?,
        render_copilot_swe_agent_settings: render_copilot_swe_agent_settings?,
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

    GitHub.dogstats.increment(event)

    enablement = params[:enablement]
    orgs = Organization.find(ids)
    orgs.each do |org|
      audit_payload[:org] = org
      audit_payload[:current_value] = enablement.to_s
      GitHub.instrument(event, audit_payload) unless %w(business enterprise).include?(enablement)
      org.plan_subscription&.synchronize_later
    end

    case enablement
    when "enable"
      copilot_business.enable_copilot_for_selected_organizations!(ids, current_user)
    when "disable"
      # This block is triggered when an individual org is disabled from the UI (at the org row level)
      # update_org_enablement will handle the case when the org is disabled from the bulk action.
      # This option is only available when business is set to allow_for_selected_orgs
      copilot_business.disable_copilot_for_selected_organizations!(ids, current_user)
    when "business"
      copilot_business.enable_copilot_for_selected_organizations!(ids, current_user) if copilot_business.copilot_enabled_for_selected_organizations?
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
      copilot_business.enable_copilot_for_selected_organizations!(ids, current_user) if copilot_business.copilot_enabled_for_selected_organizations?

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
    return if !copilot_business.copilot_billable? && !copilot_business.has_trial_organization?

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
    features << Copilot::COPILOT_SWE_AGENT if !GitHub.multi_tenant_enterprise? && copilot_business.has_copilot_enterprise_access? && !standalone_business?

    return "Enabling #{features.to_sentence} will collect additional data" if !features.empty?
    ""
  end

  sig { void }
  def mark_request_a_feature_notifications_as_read
    async_mark_threads_as_read(MemberFeatureRequest::Notification.where(entity: this_business, user: current_user))
  end
end
