# typed: true
# frozen_string_literal: true

class Businesses::SecurityCenter::SecretScanningController < Businesses::SecurityCenter::AbstractSecurityCenterController
  include SecretScanningControllerHelper

  skip_before_action :cap_pagination, unless: :robot?

  before_action :check_feature_enabled
  before_action :security_center_required

  javascript_bundle "secret-scanning"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Iam,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Notify,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql5,
    only: [:index],
    optional: true

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Iam,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    only: [:alerts_get_filter_input_suggestions]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Iam,
    ApplicationRecord::Notify,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    only: [:menu_content]

  # rubocop:disable GitHub/RailsControllerRenderLiteral
  def index
    # Redirect to strip page param when cursor pagination is enabled
    return if redirect_if_page_param_with_cursor_pagination!(scope: this_business)

    locals = {
      sso_payload:,
      has_intro: true,
      show_secret_scanning_getting_started_info: this_business.show_security_center_getting_started_info?
    }
    user_repos_in_scope = AdvancedSecurity::Features::Business::AdvancedSecurity.new(this_business).feature_available_for_user_repositories?

    if this_business.trial_getting_started_pages_viewing_required? && !this_business.secret_scanning_page_viewed?
      this_business.mark_secret_scanning_page_viewed
    end

    # We skip these cases for EMU businesses since they may have user-owned repositories with alerts
    if current_user_can_manage_settings(this_business) && !this_business.enterprise_managed? && this_business.organizations.empty?
      success = true
      return render "businesses/security_center/secret_scanning/index", locals: locals.merge({
        main_section: rendered_no_organizations_to_show_component(this_business)
      })
    end
    if current_user_can_manage_settings(this_business) && !this_business.enterprise_managed? && !has_repositories_in_enterprise? && this_business.organizations_for_member(current_user, type: :admin).any?
      success = true
      return render "businesses/security_center/secret_scanning/index", locals: locals.merge({
        main_section: rendered_no_active_repositories_enterprise_component(this_business, current_user)
      })
    end
    if current_user_can_manage_settings(this_business) && !this_business.enterprise_managed? && has_repositories_in_enterprise? && !has_secret_scanning_enabled_in_enterprise?
      success = true
      return render "businesses/security_center/secret_scanning/index", locals: locals.merge({
        main_section: rendered_not_enabled_enterprise_component(this_business)
      })
    end

    # Check whether we're also going to load alerts from EMU repositories
    # If so, then the CAP filter just means we won't have any alerts from orgs
    if authorized_orgs.empty? && !user_repos_in_scope
      success = true
      return render "businesses/security_center/secret_scanning/index", locals: locals.merge({
        main_section: rendered_no_repos_to_show_component
      })
    end

    # default to only showing open alerts if no other filter is provided (i.e. on first load)
    default_query = "is:open results:default"
    params[:query] = default_query if params[:query].nil? || params[:query] == "is:open"

    cursor_pagination_enabled = acv_cursor_pagination_enabled?(this_business)
    pagination_tags = ["scope:business", "cursor_pagination:#{cursor_pagination_enabled}"]

    GitHub.dogstats.distribution("secret_scanning.index.page", current_page, tags: pagination_tags)

    alerts, open_alert_count, closed_alert_count, response, request_error = GitHub.dogstats.distribution_time("secret_scanning.acv.alerts.duration", tags: pagination_tags) do
      get_alerts_with_cursors
    end

    if request_error.present?
      GitHub.logger.error(
        "Unable to fetch secret scanning alerts",
        "code.namespace": self.class.name,
        "code.function": __method__.to_s,
        "controller.name": self.class.name,
        "controller.action": __method__.to_s,
        "business.id": this_business.id,
        "exception.type": "AlertQueryServiceError",
        "exception.message": request_error
      )
      SecretScanning::Util::Stats.track_graceful_failure(env)

      return render "businesses/security_center/secret_scanning/index", locals: locals.merge({
        main_section: rendered_loading_secrets_failed_component
      })
    end

    blankslate_in_table = alert_centric_view_blankslate(
      alerts_present: alerts.present?,
      closed_alert_count: closed_alert_count,
      default_query: default_query,
      no_alerts_enable_on_all_repos: current_user_can_manage_settings(this_business) && !has_secret_scanning_enabled_on_all_repos_in_enterprise?,
      open_alert_count: open_alert_count,
      query: params[:query],
    )

    custom_patterns_available = SecretScanning::Features::Business::CustomPatterns.new(this_business).feature_available?

    if user_repos_in_scope
      repos_for_alerts = alerts.map(&:repository).uniq { |repo| repo.id }
      fgp = SecretScanning::AccessControl::FineGrainedPermissions
      locked_repos = fgp.get_unlockable_user_repos(current_user, repos_for_alerts)
    end

    plaid_ui_filters_enabled = current_user.feature_flag_enabled?(SecretScanning::Features::FeatureFlagHelper::FeatureFlags::PLAID_UI_FILTERS, default: true)
    partner_metadata_filters_enabled = GitHub.secret_scanning_extended_metadata_available_on_instance? && SecretScanning::Features::FeatureFlagHelper.feature_flag_enabled_in_hierarchy?(this_business, SecretScanning::Features::FeatureFlagHelper::FeatureFlags::ACV_BIZ_ORG_PARTNER_METADATA_FILTERS)

    render "businesses/security_center/secret_scanning/index", locals: locals.merge({
      main_section: SecretScanning::AlertCentricView::AlertsComponent.new(
        user: current_user,
        scope: this_business,
        alerts: alerts,
        blankslate: blankslate_in_table,
        closed_alert_count: closed_alert_count,
        filter_option_paths: get_secret_scanning_filter_option_paths(this_business, params[:query]),
        open_alert_count: open_alert_count,
        page: current_page,
        query: params[:query],
        show_org_level_suggestions: true,
        show_business_level_suggestions: true,
        show_user_repo_suggestions: user_repos_in_scope,
        locked_repos: locked_repos,
        filter_suggestions_path: method(:filter_suggestions_path),
        custom_patterns_available: custom_patterns_available,
        menu_data_list: menu_data_list,
        show_results_selector: low_conf_secrets_available,
        show_plaid_ui_filters: plaid_ui_filters_enabled,
        unresolved_generic_alert_count: (low_conf_secrets_available && !plaid_ui_filters_enabled) ? generic_results_alert_count : nil,
        next_cursor: cursor_pagination_enabled ? extract_next_cursor(response) : nil,
        prev_cursor: cursor_pagination_enabled ? extract_prev_cursor(response) : nil,
        cursor_pagination_enabled: cursor_pagination_enabled,
        partner_metadata_filters_enabled: partner_metadata_filters_enabled
      ).render_in(view_context)
    })
  end

  def alerts_get_filter_input_suggestions # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.json do
        filter_options, service_error = alert_service.get_filter_options(filter: params[:suggestion])
        suggestion_items = if service_error
          []
        else
          filter_options.flat_map do |group|
            group[:items].map do |item|
              mapped_item = { value: item[:slug] }
              mapped_item[:description] = item[:description] unless item[:description].nil?
              mapped_item
            end
          end
        end

        render json: suggestion_items
      end
    end
  end

  def menu_content # rubocop:todo GitHub/UseRestfulActions
    dropdown_enum = params[:dropdown_enum]
    menu_id = params[:menu_id]
    qualifier = params[:qualifier]
    is_multiselect = params[:is_multiselect]

    if authorized_orgs.empty?
      return render(
        Primer::Experimental::SelectMenu::ListComponent.new(
          id: "#{menu_id}-empty-list",
          test_selector: "filter-options-empty"
        ).tap do |list|
          list.with_message { "Nothing to show" }
        end,
        layout: false,
      )
    end

    service = SecretScanning::AlertQueryService.for_business(
      business: this_business,
      organizations: authorized_orgs,
      query: params[:query],
      current_user: current_user,
      user_session: user_session
    )
    filter_options, service_error = service.get_filter_options(filter: dropdown_enum)
    if service_error
      GitHub.logger.error(
        "Unable to fetch filter options",
        "code.namespace": self.class.name,
        "code.function": __method__.to_s,
        "controller.name": self.class.name,
        "controller.action": __method__.to_s,
        "business.id": this_business.id,
        "exception.type": "AlertQueryServiceError",
        "exception.message": service_error
      )
      return render_404
    end

    render_filter_content_component(filter_options, menu_id, qualifier, is_multiselect)
  end

  private

  sig { override.returns(Symbol) }
  def authorized_orgs_actions
    :view_secret_scanning_alerts
  end

  sig { returns(SecretScanning::AlertQueryService) }
  memoize def alert_service
    SecretScanning::AlertQueryService.for_business(
      business: this_business,
      organizations: authorized_orgs,
      query: params[:query],
      current_user: current_user,
      user_session: user_session
    )
  end

  memoize def parsed_query
    alert_service.parsed_query
  end

  memoize def get_alerts_with_cursors
    fetch_alerts_with_cursor_pagination(alert_service, scope: this_business)
  end

  def filter_suggestions_path(suggestion: nil)
    return security_center_options_enterprise_path("options-type": "teams") if suggestion == "team"
    return security_center_options_enterprise_path("options-type": "topics") if suggestion == "topic"
    security_center_alerts_secret_scanning_alerts_get_filter_input_suggestions_enterprise_path(suggestion: suggestion, query: params[:query])
  end

  def menu_data_list
    [
      ::SecurityCenter::SelectPanelComponent::Data.new(
        title: "Teams",
        header: "Filter by team",
        options_src: security_center_options_enterprise_path({
          "options-type": "teams",
          qualifier: ::Search::Queries::SecurityCenter::SecretScanningQuery::QUALIFIER_TEAM,
          query: parsed_query.query,
          multiselect: true
        }),
      )
    ]
  end

  def check_feature_enabled
    token_scanning = SecretScanning::Features::Business::TokenScanning.new(this_business)
    render_404 unless token_scanning.feature_available?
  end

  def has_repositories_in_enterprise?
    RepositorySecurityCenterConfig
      .where(business_id: this_business.id)
      .exists?
  end

  def has_secret_scanning_enabled_in_enterprise?
    RepositorySecurityCenterConfig
      .where(business_id: this_business.id)
      .joins(:repository_security_center_statuses)
      .where(repository_security_center_statuses: {
        feature_type: :secret_scanning,
        scanning_status: :enrolled
      })
      .exists?
  end

  def has_secret_scanning_enabled_on_all_repos_in_enterprise?
    repo_without_ss_exists = RepositorySecurityCenterConfig
      .where(business_id: this_business.id)
      .where.not(
        repository_id: RepositorySecurityCenterStatus
          .where(feature_type: :secret_scanning, scanning_status: :enrolled)
          .select(:repository_id)
      )
      .exists?

    return false if repo_without_ss_exists

    # If no repos without SS, check if at least one repo exists (which would mean all of them have SS)
    has_repositories_in_enterprise?
  end

  def low_conf_secrets_available
    SecretScanning::Features::Business::GenericSecrets.new(this_business).feature_available? ||
      SecretScanning::Features::Business::LowerConfidencePatterns.new(this_business).feature_available?
  end

  memoize def generic_results_alert_count
    return nil unless low_conf_secrets_available
    default_query_lc = Search::Queries::SecurityCenter::SecretScanningQuery::default_query_generic_results
    svc = SecretScanning::AlertQueryService.for_business(
      business: this_business,
      organizations: authorized_orgs,
      query: default_query_lc,
      current_user: current_user,
      user_session: user_session
    )
    svc.generic_results_alert_count
  end
end
