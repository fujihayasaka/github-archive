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
    only: [:alerts_get_filter_input_suggestions]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Iam,
    ApplicationRecord::Notify,
    ApplicationRecord::Collab,
    only: [:menu_content]

  # rubocop:disable GitHub/RailsControllerRenderLiteral
  def index
    locals = { cap_filter: cap_filter, unauthorized_orgs: unauthorized_orgs }
    user_repos_in_scope = AdvancedSecurity::Features::Business::AdvancedSecurity.new(this_business).feature_available_for_user_repositories?

    # Check whether we're also going to load alerts from EMU repositories
    # If so, then the CAP filter just means we won't have any alerts from orgs
    if authorized_orgs.empty? && !user_repos_in_scope
      success = true
      return render "businesses/security_center/secret_scanning/index", locals: locals.merge({
        main_section: rendered_no_repos_to_show_component
      })
    end

    # default to only showing open alerts if no other filter is provided (i.e. on first load)
    params[:query] = "is:open results:default" if params[:query].nil?

    GitHub.dogstats.distribution("secret_scanning.index.page", current_page, tags: ["scope:business"])

    alerts, open_alert_count, closed_alert_count, _, request_error = alert_service.get_alerts(page: current_page, per_page: DEFAULT_PER_PAGE)

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

    blankslate_in_table =
      if open_alert_count == 0 && params[:query] == "is:open"
        BLANKSLATE_NO_OPEN_SECRETS
      elsif open_alert_count == 0 && params[:query] == "is:open #{Search::Queries::SecurityCenter::SecretScanningQuery::QUALIFIER_RESULTS_CATEGORY}:#{Search::Queries::SecurityCenter::SecretScanningQuery::EXPERIMENTAL_RESULTS}"
        BLANKSLATE_NO_EXPERIMENTAL_MATCHES
      elsif !alerts.present?
        BLANKSLATE_NO_MATCHES
      end

    custom_patterns_available = SecretScanning::Features::Business::CustomPatterns.new(this_business).feature_available?

    if user_repos_in_scope
      repos_for_alerts = alerts.map(&:repository).uniq { |repo| repo.id }
      fgp = SecretScanning::AccessControl::FineGrainedPermissions
      locked_repos = fgp.get_unlockable_user_repos(current_user, repos_for_alerts)
    end


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
        unresolved_experimental_alert_count: experimental_results_alert_count
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

  def filter_suggestions_path(suggestion: nil)
    return security_center_options_enterprise_path("options-type": "teams") if suggestion == "team"
    return security_center_options_enterprise_path("options-type": "topics") if suggestion == "topic"
    security_center_alerts_secret_scanning_alerts_get_filter_input_suggestions_enterprise_path(suggestion: suggestion)
  end

  def menu_data_list
    [].tap do |list|
      next if Team.owned_by(authorized_orgs).size > TEAM_DROPDOWN_THRESHOLD

      qualifier = ::Search::Queries::SecurityCenter::SecretScanningQuery::QUALIFIER_TEAM
      include_clear = parsed_query.class.qualifier_exists?(parsed_query.query, qualifier)
      clear_href = "?query=#{parsed_query.class.remove_qualifiers(parsed_query.query, [qualifier])}"

      list << ::SecurityCenter::Coverage::SelectMenuComponent::Data.new(
        name: "Teams",
        header: "Filter by team",
        filter: ::SecurityCenter::Coverage::SelectMenuComponent::Filter.new(placeholder: "Filter teams"),
        options_src: security_center_options_enterprise_path(
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

  def check_feature_enabled
    token_scanning = SecretScanning::Features::Business::TokenScanning.new(this_business)
    render_404 unless token_scanning.feature_available?
  end

  def low_conf_secrets_available
    SecretScanning::Features::Business::GenericSecrets.new(this_business).feature_available? ||
      SecretScanning::Features::Business::LowerConfidencePatterns.new(this_business).feature_available?
  end

  memoize def experimental_results_alert_count
    return nil unless low_conf_secrets_available
    default_query_lc = Search::Queries::SecurityCenter::SecretScanningQuery::default_query_experimental_results
    svc = SecretScanning::AlertQueryService.for_business(
      business: this_business,
      organizations: authorized_orgs,
      query: default_query_lc,
      current_user: current_user,
      user_session: user_session
    )
    svc.experimental_results_alert_count
  end
end
