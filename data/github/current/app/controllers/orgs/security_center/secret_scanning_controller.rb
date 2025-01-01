# typed: true
# frozen_string_literal: true

class Orgs::SecurityCenter::SecretScanningController < Orgs::SecurityCenter::AbstractSecurityCenterController
  include SecretScanningControllerHelper

  # Access checks
  before_action :organization_read_required
  before_action :feature_required
  before_action :security_center_required

  # Allow users to view all pages
  skip_before_action :cap_pagination, unless: :robot?

  # Background process
  after_action :ensure_security_overview_analytics_reconciliation, only: [:index]
  after_action :trigger_security_overview_analytics_backfill, only: [:index]

  javascript_bundle "secret-scanning"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Notify,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Iam,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters \
    ApplicationRecord::Copilot,
    ApplicationRecord::Mysql5,
    ApplicationRecord::SecurityOverviewAnalytics,
    only: [:index, :menu_content],
    optional: true

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Notify,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    only: [:menu_content]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Notify,
    ApplicationRecord::Repositories,
    ApplicationRecord::Iam,
    only: [:alerts_get_filter_input_suggestions]

  def index # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    generic_secrets_survey_url = "https://gh.io/password-survey"

    @backfill_triggered = this_organization.trigger_security_center_reconciliation

    if !has_repositories?
      success = true
      selected_tab = :secret_scanning
      if SecurityCenter::FeatureFlagHelper.split_secret_scanning_tab_counts?(this_organization, current_user)
        selected_tab = :secret_scanning_default
      end
      return render "orgs/security_center/alerts_secret_scanning", locals: {
        show_generic_secrets_survey: false,
        backfill_in_progress: @backfill_triggered,
        main_section: rendered_no_active_repositories_component,
        organization: this_organization,
        selected_tab: selected_tab,
      }
    end

    default_query = Search::Queries::SecurityCenter::SecretScanningQuery::default_query(low_conf_secrets_available)
    params[:query] = default_query if params[:query].nil?

    alerts, open_alert_count, closed_alert_count, _, request_error = get_alerts

    if request_error.present?
      GitHub.logger.error(
        "Unable to fetch secret scanning alerts",
        "code.namespace": self.class.name,
        "code.function": __method__.to_s,
        "controller.name": self.class.name,
        "controller.action": __method__.to_s,
        "organization.id": this_organization.id,
        "exception.type": "AlertQueryServiceError",
        "exception.message": request_error
      )
      SecretScanning::Util::Stats.track_graceful_failure(env)
      return render_alerts_secret_scanning_with_loading_secrets_failed_component
    end


    blankslate_in_table ||=
      if open_alert_count == 0 && params[:query] == default_query
        BLANKSLATE_NO_OPEN_SECRETS
      elsif open_alert_count == 0 && params[:query] == "is:open #{Search::Queries::SecurityCenter::SecretScanningQuery::QUALIFIER_RESULTS_CATEGORY}:#{Search::Queries::SecurityCenter::SecretScanningQuery::EXPERIMENTAL_RESULTS}"
        BLANKSLATE_NO_EXPERIMENTAL_MATCHES
      elsif !alerts.present?
        BLANKSLATE_NO_MATCHES
      end

    GitHub.dogstats.distribution("secret_scanning.index.page", current_page, tags: ["scope:organization"])

    # For org members with partial repo access, we need to show a warning if they've exceeded the max number of repos we show.
    _, repo_limit_exceeded = allowed_repository_ids_for_organization_members unless can_view_all_alerts?
    custom_patterns_available = SecretScanning::Features::Org::CustomPatterns.new(this_organization).feature_available?

    show_generic_secrets_survey = SecretScanning::Features::Org::GenericSecrets.new(this_organization).show_user_feedback_link?(current_user)

    selected_tab = :secret_scanning
    if SecurityCenter::FeatureFlagHelper.split_secret_scanning_tab_counts?(this_organization, current_user)
      qp = QUERY_PARSER.new(query: params[:query], allow_results_category: true)
      if qp.results_category == QUERY_PARSER::EXPERIMENTAL_RESULTS
        selected_tab = :secret_scanning_experimental
      else
        selected_tab = :secret_scanning_default
      end
    end

    render "orgs/security_center/alerts_secret_scanning", locals: {
      backfill_in_progress: @backfill_triggered,
      show_generic_secrets_survey: show_generic_secrets_survey,
      generic_secrets_survey_url: generic_secrets_survey_url,
      selected_tab: selected_tab,
      main_section: SecretScanning::AlertCentricView::AlertsComponent.new(
        user: current_user,
        scope: this_organization,
        alerts: alerts,
        blankslate: blankslate_in_table,
        closed_alert_count: closed_alert_count,
        filter_option_paths: get_secret_scanning_filter_option_paths(this_organization, params[:query]),
        open_alert_count: open_alert_count,
        page: current_page,
        query: params[:query],
        custom_patterns_available: custom_patterns_available,
        show_org_level_suggestions: true,
        filter_suggestions_path: method(:filter_suggestions_path),
        menu_data_list: menu_data_list,
        show_results_selector: low_conf_secrets_available,
        show_incomplete_data_warning: repo_limit_exceeded,
        unresolved_experimental_alert_count: experimental_results_alert_count
      ).render_in(view_context),
      organization: this_organization,
    }
  end

  def menu_content # rubocop:todo GitHub/UseRestfulActions
    dropdown_enum = params[:dropdown_enum]
    menu_id = params[:menu_id]
    qualifier = params[:qualifier]
    is_multiselect = params[:is_multiselect]

    filter_options, service_error = alert_service.get_filter_options(filter: dropdown_enum)
    return render_404 if service_error

    render_filter_content_component(filter_options, menu_id, qualifier, is_multiselect)
  end

  def alerts_get_filter_input_suggestions # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.json do
        filter_options, service_error = alert_service.get_filter_options(filter: params[:suggestion])

        include_description = [GroupByAggregation::TOKEN_TYPE, GroupByAggregation::TOKEN_PROVIDER].include?(params[:suggestion])
        suggestion_items = if service_error
          []
        else
          filter_options.flat_map do |group|
            group[:items].map do |item|
              mapped_item = { value: item[:slug] }
              mapped_item[:description] = item[:label] if include_description
              mapped_item
            end
          end
        end

        render json: suggestion_items
      end
    end
  end

  private

  def feature_required
    token_scanning = SecretScanning::Features::Org::TokenScanning.new(this_organization)
    render_404 unless token_scanning.feature_available?
  end

  def has_repositories?
    active_repos = RepositorySecurityCenterConfig.where(owner_id: this_organization.id)
    active_repos.size > 0
  end

  def render_alerts_secret_scanning_with_loading_secrets_failed_component
    selected_tab = :secret_scanning
    if SecurityCenter::FeatureFlagHelper.split_secret_scanning_tab_counts?(this_organization, current_user)
      selected_tab = :secret_scanning_default
    end
    render "orgs/security_center/alerts_secret_scanning", locals: {
      show_generic_secrets_survey: false,
      backfill_in_progress: @backfill_triggered,
      main_section: rendered_loading_secrets_failed_component,
      organization: this_organization,
      selected_tab: selected_tab,
    }
  end

  def alert_service
    kwargs = { organization: this_organization, query: params[:query], current_user: current_user, user_session: user_session }
    unless can_view_all_alerts?
      allowed_repo_ids, _ = allowed_repository_ids_for_organization_members
      kwargs[:allowed_repository_ids] = allowed_repo_ids
    end
    SecretScanning::AlertQueryService.for_organization(**kwargs)
  end

  def allowed_repository_ids_for_organization_members
    allowed_repository_ids_by_feature_for_organization_members[SecurityCenter::SecurityFeatures::SECRET_SCANNING]
  end

  def table_alerts_count
    _, open_count, closed_count, _, _ = get_alerts

    if parsed_query.is_open_page?
      open_count
    elsif parsed_query.is_closed_page?
      closed_count
    else
      open_count + closed_count
    end
  end

  memoize def parsed_query
    alert_service.parsed_query
  end

  memoize def get_alerts
    alert_service.get_alerts(page: current_page, per_page: DEFAULT_PER_PAGE)
  end

  def filter_suggestions_path(suggestion: nil)
    if suggestion&.start_with?("props.")
      prop_name = suggestion.split(".", 2).last
      security_center_options_path("options-type": "props", "name": prop_name)
    elsif suggestion == "team"
      security_center_options_path("options-type": "teams")
    elsif suggestion == "topic"
      security_center_options_path("options-type": "topics")
    else
      security_center_alerts_secret_scanning_get_filter_input_suggestions_path(suggestion: suggestion)
    end
  end

  def menu_data_list
    [].tap do |list|
      next if this_organization.teams.size > TEAM_DROPDOWN_THRESHOLD

      qualifier = ::Search::Queries::SecurityCenter::SecretScanningQuery::QUALIFIER_TEAM
      include_clear = parsed_query.class.qualifier_exists?(parsed_query.query, qualifier)
      clear_href = "?query=#{parsed_query.class.remove_qualifiers(parsed_query.query, [qualifier])}"

      list << ::SecurityCenter::Coverage::SelectMenuComponent::Data.new(
        name: "Teams",
        header: "Filter by team",
        filter: ::SecurityCenter::Coverage::SelectMenuComponent::Filter.new(placeholder: "Filter teams"),
        options_src: security_center_options_path(
          "options-type": "teams",
          qualifier: qualifier,
          query: parsed_query.query,
          multiselect: true,
        ),
        clear_option: (::SecurityCenter::Coverage::SelectMenuComponent::ClearOption.new(
          text: "Clear teams",
          href: clear_href,
        ) if include_clear),
      )
    end
  end

  def low_conf_secrets_available
    SecretScanning::Features::Org::GenericSecrets.new(this_organization).feature_available? ||
      SecretScanning::Features::Org::LowerConfidencePatterns.new(this_organization).feature_available?
  end

  memoize def experimental_results_alert_count
    return nil unless low_conf_secrets_available
    default_query_lc = Search::Queries::SecurityCenter::SecretScanningQuery::default_query_experimental_results
    kwargs = { organization: this_organization, query: default_query_lc, current_user: current_user, user_session: user_session }
    unless can_view_all_alerts?
      allowed_repo_ids, _ = allowed_repository_ids_for_organization_members
      kwargs[:allowed_repository_ids] = allowed_repo_ids
    end
    svc = SecretScanning::AlertQueryService.for_organization(**kwargs)
    svc.experimental_results_alert_count
  end
end
