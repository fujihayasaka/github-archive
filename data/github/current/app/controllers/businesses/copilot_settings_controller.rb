# typed: strict
# frozen_string_literal: true

class Businesses::CopilotSettingsController < Businesses::BusinessController
  extend T::Sig

  before_action :dotcom_required
  before_action :business_owner_required
  before_action :business_not_downgraded_to_free_plan_required
  before_action :check_business_is_not_trial_without_cfb_trial, except: [:show_first_run_flow_cta]
  before_action :check_business_is_copilot_billable, only: [:update, :update_copilot_enablement, :update_individual_org_enablement, :update_bulk_org_enablement]
  before_action :check_valid_enablement_option, only: [:update_individual_org_enablement, :update_bulk_org_enablement]
  before_action :check_business_set_to_selected, only: [:update_individual_org_enablement, :update_bulk_org_enablement]
  before_action :mark_request_a_feature_notifications_as_read, only: [:index]
  before_action :check_business_can_use_content_exclusions, only: [:update_content_exclusion]
  before_action :parse_json_params, only: [:update_content_exclusion]

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

  allow_verified_fetch only: [:update_copilot_enablement, :update_content_exclusion]

  PER_PAGE = 10
  BAD_SELECTION_ERROR_MESSAGE = "Select an option below to continue."
  BAD_ENABLEMENT_ERROR_MESSAGE = "You must allow for specific organizations to use GitHub Copilot to continue."
  COPILOT_PUBLIC_CODE_SUGGESTIONS_UPDATED_MESSAGE = "Suggestions matching public code policy has been updated."
  COPILOT_EDITOR_CHAT_UPDATED_MESSAGE = "Copilot Chat in the IDE policy has been updated."
  COPILOT_MOBILE_CHAT_UPDATED_MESSAGE = "Copilot Chat in GitHub Mobile policy has been updated."
  COPILOT_CHAT_UPDATED_MESSAGE = "Copilot Chat in the IDEs and Mobile policy has been updated."
  COPILOT_GITHUB_CHAT_UPDATED_MESSAGE = "Copilot Chat in github.com policy has been updated."
  COPILOT_FOR_CLI_UPDATED_MESSAGE = "Copilot in the CLI policy has been updated."
  COPILOT_IN_DOTCOM_UPDATED_MESSAGE = "Copilot in github.com policy has been updated."
  BING_IN_DOTCOM_UPDATED_MESSAGE = "Bing for Copilot in github.com policy has been updated."
  USER_FEEDBACK_OPT_IN_MESSAGE = "Copilot user feedback opt in policy has been updated."
  COPILOT_CUSTOM_MODELS_UPDATED_MESSAGE = "GitHub Copilot fine-tuning policy has been updated."
  COPILOT_ENABLED_FOR_BUSINESS = "GitHub Copilot has been enabled for your enterprise."
  COPILOT_DISABLED_FOR_BUSINESS = "GitHub Copilot has been disabled for your enterprise."
  COPILOT_ENABLED_FOR_SELECTED = "GitHub Copilot has been enabled for specified organizations."
  COPILOT_ENABLED_FOR_ALL = "GitHub Copilot has been enabled for all organizations."
  COPILOT_EXTENSIONS_UPDATED_MESSAGE = "GitHub Copilot Extensions policy has been updated."
  COPILOT_PLAN_SCHEDULED_DOWNGRADE = "An organization has been scheduled to downgrade to Copilot Business. Download the report to see which seats are billed for the current billing cycle."
  COPILOT_BETA_FEATURES_IN_DOTCOM_UPDATED_MESSAGE = "Preview features for Copilot in github.com policy has been updated."
  PRIVATE_TELEMETRY_UPDATED_MESSAGE = "GitHub Private Telemetry policy has been updated."
  COPILOT_USAGE_METRICS_UPDATED_MESSAGE = T.let("GitHub #{Copilot::COPILOT_METRICS_API_NAME} access policy has been updated.", String)

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
      flash[:notice] = COPILOT_PUBLIC_CODE_SUGGESTIONS_UPDATED_MESSAGE
    when "no_policy"
      copilot_business.no_public_code_suggestions_policy!
      flash[:notice] = COPILOT_PUBLIC_CODE_SUGGESTIONS_UPDATED_MESSAGE
    when "blocked"
      copilot_business.block_public_code_suggestions!
      flash[:notice] = COPILOT_PUBLIC_CODE_SUGGESTIONS_UPDATED_MESSAGE
    end

    case params[:copilot_editor_chat_enabled]
    when "enabled"
      copilot_business.enable_chat!
      flash[:notice] = COPILOT_EDITOR_CHAT_UPDATED_MESSAGE
    when "disabled"
      copilot_business.disable_chat!
      flash[:notice] = COPILOT_EDITOR_CHAT_UPDATED_MESSAGE
    when "no_policy"
      copilot_business.no_chat_policy!
      flash[:notice] = COPILOT_EDITOR_CHAT_UPDATED_MESSAGE
    end

    # TODO: update methods once mobile chat configuration methods are set up
    case params[:copilot_mobile_chat]
    when "enabled"
      copilot_business.enable_mobile_chat!
      flash[:notice] = COPILOT_MOBILE_CHAT_UPDATED_MESSAGE
    when "disabled"
      copilot_business.disable_mobile_chat!
      flash[:notice] = COPILOT_MOBILE_CHAT_UPDATED_MESSAGE
    when "no_policy"
      copilot_business.mobile_chat_no_policy!
      flash[:notice] = COPILOT_MOBILE_CHAT_UPDATED_MESSAGE
    end

    if this_business.feature_enabled?(:copilot_custom_models)
      case params[:copilot_custom_models]
      when "enabled"
        copilot_business.custom_models_enabled!
        flash[:notice] = COPILOT_CUSTOM_MODELS_UPDATED_MESSAGE
      when "disabled"
        copilot_business.custom_models_disabled!
        flash[:notice] = COPILOT_CUSTOM_MODELS_UPDATED_MESSAGE
      when "no_policy"
        copilot_business.custom_models_no_policy!
        flash[:notice] = COPILOT_CUSTOM_MODELS_UPDATED_MESSAGE
      end
    end

    case params[:copilot_dotcom_chat]
    when "enabled"
      copilot_business.dotcom_chat_enabled!
      flash[:notice] = COPILOT_GITHUB_CHAT_UPDATED_MESSAGE
    when "disabled"
      copilot_business.disable_dotcom_chat!
      flash[:notice] = COPILOT_GITHUB_CHAT_UPDATED_MESSAGE
    when "no_policy"
      copilot_business.dotcom_chat_no_policy!
      flash[:notice] = COPILOT_GITHUB_CHAT_UPDATED_MESSAGE
    end

    case params[:cli]
    when "enabled"
      copilot_business.cli_enabled!
      flash[:notice] = COPILOT_FOR_CLI_UPDATED_MESSAGE
    when "disabled"
      copilot_business.cli_disabled!
      flash[:notice] = COPILOT_FOR_CLI_UPDATED_MESSAGE
    when "no_policy"
      copilot_business.cli_no_policy!
      flash[:notice] = COPILOT_FOR_CLI_UPDATED_MESSAGE
    end

    if (
      copilot_business.has_copilot_enterprise_access? ||
      this_business.feature_enabled?(:copilot_mixed_licenses) ||
      copilot_business.has_trial_organization?
    )
      case params[:bing_github_chat]
      when "enabled"
        copilot_business.bing_github_chat_enable!
        flash[:notice] = BING_IN_DOTCOM_UPDATED_MESSAGE
      when "disabled"
        copilot_business.bing_github_chat_disable!
        flash[:notice] = BING_IN_DOTCOM_UPDATED_MESSAGE
      when "no_policy"
        copilot_business.bing_github_chat_no_policy!
        flash[:notice] = COPILOT_IN_DOTCOM_UPDATED_MESSAGE
      end
    end

    if copilot_business.has_copilot_enterprise_access? || this_business.feature_enabled?(:copilot_mixed_licenses)
      case params[:copilot_for_dotcom]
      when "enabled"
        copilot_business.copilot_for_dotcom_enabled!
        flash[:notice] = COPILOT_IN_DOTCOM_UPDATED_MESSAGE
      when "disabled"
        copilot_business.copilot_for_dotcom_disabled!
        flash[:notice] = COPILOT_IN_DOTCOM_UPDATED_MESSAGE
      when "no_policy"
        copilot_business.copilot_for_dotcom_no_policy!
        flash[:notice] = COPILOT_IN_DOTCOM_UPDATED_MESSAGE
      end

      case params[:copilot_user_feedback_opt_in]
      when "enabled"
        copilot_business.enable_user_feedback!
        flash[:notice] = USER_FEEDBACK_OPT_IN_MESSAGE
      when "disabled"
        copilot_business.disable_user_feedback!
        flash[:notice] = USER_FEEDBACK_OPT_IN_MESSAGE
      end
    end

    case params[:copilot_extensions]
    when "enabled"
      copilot_business.copilot_extensions_enabled!
      flash[:notice] = COPILOT_EXTENSIONS_UPDATED_MESSAGE
    when "disabled"
      copilot_business.copilot_extensions_disabled!
      flash[:notice] = COPILOT_EXTENSIONS_UPDATED_MESSAGE
    when "no_policy"
      copilot_business.copilot_extensions_no_policy!
      flash[:notice] = COPILOT_EXTENSIONS_UPDATED_MESSAGE
    end

    case params[:copilot_beta_features_opt_in]
    when "enabled"
      copilot_business.beta_features_github_chat_enable!
      flash[:notice] = COPILOT_BETA_FEATURES_IN_DOTCOM_UPDATED_MESSAGE
    when "disabled"
      copilot_business.beta_features_github_chat_disable!
      flash[:notice] = COPILOT_BETA_FEATURES_IN_DOTCOM_UPDATED_MESSAGE
    when "no_policy"
      copilot_business.beta_features_github_chat_no_policy!
      flash[:notice] = COPILOT_IN_DOTCOM_UPDATED_MESSAGE
    end

    case params[:private_telemetry]
    when "allowed"
      copilot_business.private_telemetry_enabled!
      flash[:notice] = PRIVATE_TELEMETRY_UPDATED_MESSAGE
    when "blocked"
      copilot_business.private_telemetry_disabled!
      flash[:notice] = PRIVATE_TELEMETRY_UPDATED_MESSAGE
    when "no_policy"
      copilot_business.private_telemetry_no_policy!
      flash[:notice] = PRIVATE_TELEMETRY_UPDATED_MESSAGE
    end

    if this_business.feature_enabled?(:copilot_usage_metrics_policy)
      case params[:copilot_telemetry_aggregation]
      when "enabled"
        copilot_business.telemetry_aggregation_enabled!
        flash[:notice] = COPILOT_USAGE_METRICS_UPDATED_MESSAGE
      when "disabled"
        copilot_business.telemetry_aggregation_disabled!
        flash[:notice] = COPILOT_USAGE_METRICS_UPDATED_MESSAGE
      when "no_policy"
        copilot_business.telemetry_aggregation_no_policy!
        flash[:notice] = COPILOT_USAGE_METRICS_UPDATED_MESSAGE
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
    end


    if params[:return_to]
      safe_redirect_to(params[:return_to])
    else
      redirect_to settings_copilot_enterprise_path(copilot_business, tab: get_tab)
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
        Copilot::SeatAssignment.for_standalone_business(this_business).map(&:assignable),
        current_user
      ) if standalone_business?
      flash[:notice] = COPILOT_DISABLED_FOR_BUSINESS
    when "all_organizations"
      copilot_business.enable_copilot_for_all_organizations!(current_user)
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
    save_org_enablement_changes(ids: [params[:organization_id].to_i])

    organization = Organization.find(params[:organization_id])
    copilot_organization = Copilot::Organization.new(organization)

    if params[:reenable] == "true"
      flash[:notice] = "GitHub Copilot has been re-enabled for #{organization.display_login}."
    elsif params[:enablement] == "business" && copilot_organization.copilot_plan_enterprise?
      flash[:notice] = COPILOT_PLAN_SCHEDULED_DOWNGRADE
    elsif params[:enablement] == "business"
      flash[:notice] = "#{organization.display_login} has been granted access to Copilot Business. Organization administrators will receive an email with details and will be able to manage seats with the plan selected."
    elsif params[:enablement] == "enterprise"
      flash[:notice] = "#{organization.display_login} has been granted access to Copilot Enterprise. Organization administrators will receive an email with details and will be able to manage seats with the plan selected."
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

  private

  sig { returns(Copilot::Business) }
  def copilot_business # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @copilot_business ||= T.let(Copilot::Business.new(this_business), T.nilable(Copilot::Business))
  end

  sig { void }
  def check_business_set_to_selected
    return if this_business.feature_enabled?(:copilot_mixed_licenses)
    render_index(organizations: paginated_orgs, error: BAD_ENABLEMENT_ERROR_MESSAGE) unless copilot_business.copilot_enabled_for_selected_organizations?
  end

  sig { void }
  def check_valid_enablement_option
    if this_business.feature_enabled?(:copilot_mixed_licenses)
      render_index(organizations: paginated_orgs, error: BAD_SELECTION_ERROR_MESSAGE) unless %w[enable disable business enterprise].include?(params[:enablement])
    else
      render_index(organizations: paginated_orgs, error: BAD_SELECTION_ERROR_MESSAGE) unless %w[enable disable].include?(params[:enablement])
    end
  end

  sig { void }
  def check_business_is_copilot_billable
    render_404 unless copilot_business.copilot_billable?
  end

  sig { void }
  def check_business_is_not_trial_without_cfb_trial
    render_404 if this_business.trial? && !copilot_business.has_trial_organization?
  end

  sig { void }
  def check_business_can_use_content_exclusions
    render_404 unless copilot_business.content_exclusion_available?
  end

  sig { params(organizations: T::Array[::Organization], error: T.nilable(String)).void }
  def render_index(organizations:, error: nil)
    Copilot::Instrumenter.instrument_clickwrap_shown(current_user, this_business)
    if standalone_business?
      render_standalone_index(error: error)
    else
      render "businesses/copilot_settings/index", locals: {
        copilot_business: copilot_business,
        organizations: organizations,
        title: "GitHub Copilot",
        tab: get_tab || "access",
        error: error,
        copilot_custom_models: this_business.feature_enabled?(:copilot_custom_models),
        features_for_data_retention: get_features_for_data_retention,
        feature_requests: feature_requests_count_by_organizations,
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
    return {} unless copilot_business.content_exclusion_available?
    config = Copilot::ContentExclusionConfiguration.for_business(this_business).first

    # Keep types in sync with ui/packages/copilot-content-exclusion/partials/IgnoreForm.tsx#Payload
    {
      updateEndpoint: update_settings_copilot_content_exclusion_enterprise_path(this_business),
      lastEditedBy: config&.updated_by ? { login: config.updated_by.display_login, time: config.updated_at, link: content_exclusions_audit_link } : nil,
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
    MemberFeatureRequest.active_request_entities.where(billing_entity: this_business)
  end

  sig { returns(ActiveRecord::Relation) }
  memoize def feature_requests_from_members_of_organizations
    MemberFeatureRequest.active_request_entities.where(billing_entity: this_business.organizations.pluck(:id))
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
          old_plan = copilot_org.copilot_plan
          copilot_org.copilot_plan_business!
          Copilot::Instrumenter.instrument_copilot_plan_changed(current_user, org, old_plan, "business")
        end
      end
    when "enterprise"
      copilot_business.enable_copilot_for_selected_organizations!(ids, current_user) if copilot_business.copilot_enabled_for_selected_organizations?

      orgs.each do |org|
        copilot_org = Copilot::Organization.new(org)
        old_plan = copilot_org.copilot_plan
        copilot_org.copilot_plan_enterprise!
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
    return if !copilot_business.copilot_billable?
    return if params[:tab] == "content-exclusion" && !copilot_business.content_exclusion_available?

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

    return "Enabling #{features.to_sentence} will collect additional data" if !features.empty?
    ""
  end

  sig { void }
  def mark_request_a_feature_notifications_as_read
    async_mark_threads_as_read(MemberFeatureRequest::Notification.where(entity: this_business, user: current_user))
  end
end
