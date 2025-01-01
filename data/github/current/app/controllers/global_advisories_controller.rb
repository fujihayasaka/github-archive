# typed: true
# frozen_string_literal: true

class GlobalAdvisoriesController < ApplicationController
  include GitHub::RateLimitedRequest

  before_action :require_advisory, except: [:index, :cwe_filter]
  before_action :login_required, only: [:organization_filter]
  skip_before_action :cap_pagination, only: [:index], unless: :robot?

  rate_limit_requests(
    only: :index,
    key: :search_rate_limit_key,
    max: :search_rate_limit_max,
    ttl: GitHub::RateLimitedRequest::LEGACY_DEFAULT_RATE_LIMIT_TTL,
    at_limit: :search_rate_limit_record,
  )

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Notify,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Iam,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Billing,
    only: [:dependabot_alerts]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Notify,
    ApplicationRecord::Collab,
    only: [:cwe_filter]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Notify,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Iam,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    only: [:dependabot_alerts_count]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Notify,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Spokes,
    only: [:history]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Notify,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Iam,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Notify,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    only: [:organization_filter]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Notify,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:dependabot_alerts, :index, :show],
    optional: true

  PER_PAGE = 25

  def index
    query = vulnerability_query

    results = begin
      query.execute
    rescue StandardError => boom # rubocop:todo Lint/GenericRescue
      Failbot.report(boom)
      Search::Results.empty
    end

    view = create_view_model(
      GlobalAdvisories::IndexView,
      query: query,
      results: results,
      ecosystem_counts: ecosystem_counts,
      reviewed_advisory_count: reviewed_advisory_count,
      unreviewed_advisory_count: unreviewed_advisory_count,
    )
    render "global_advisories/index", locals: { view: view }
  end

  def show
    override_analytics_location "/advisories/<id>"

    view = create_view_model(
      GlobalAdvisories::ShowView,
      advisory: advisory,
    )
    set_hovercard_subject(advisory)
    render "global_advisories/show", locals: { view: view }

    GlobalInstrumenter.instrument("security_advisory.show", {
      actor: current_user,
      security_advisory_id: advisory.id,
    })
  end

  def dependabot_alerts # rubocop:todo GitHub/UseRestfulActions
    override_analytics_location "/advisories/<id>/dependabot"

    view = create_view_model(
      GlobalAdvisories::ShowView,
      advisory: advisory,
      repository_alerts_scope: repository_alerts_scope,
      open_alerts_count: open_alerts_count,
      closed_alerts_count: closed_alerts_count,
      query: dependabot_alerts_query,
      dependabot_alerts_tab: true,
    )

    return render_404 unless view.show_dependabot_alerts_tab?

    mark_threads_as_read

    render "global_advisories/show", locals: { view: view }
  end

  def dependabot_alerts_count # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html_fragment do
        render partial: "global_advisories/dependabot_alerts_count", locals: {
          count: open_alerts_count,
        }, formats: :html
      end

      format.all do
        render_404
      end
    end
  end

  def cwe_filter # rubocop:todo GitHub/UseRestfulActions
    render partial: "global_advisories/cwe_filter", locals: {
      view: create_view_model(GlobalAdvisories::IndexView, query: vulnerability_query)
    }
  end

  def organization_filter # rubocop:todo GitHub/UseRestfulActions
    render partial: "global_advisories/organization_filter", locals: {
      view: create_view_model(GlobalAdvisories::ShowView, query: dependabot_alerts_query, advisory: advisory)
    }
  end

  def history # rubocop:todo GitHub/UseRestfulActions
    render partial: "global_advisories/history", locals: {
      view: create_view_model(GlobalAdvisories::HistoryView, advisory: advisory)
    }
  end

  private

  def parsed_query
    Search::Queries::VulnerabilityQuery.stringify(
      Search::Queries::VulnerabilityQuery.parse(params[:query]),
    )
  end

  def show_closed_alerts?
    dependabot_alerts_query.closed?
  end

  memoize def open_alerts_count
    ActiveRecord::Base.connected_to(role: :reading) do
      base_repository_alerts_scope.open.count
    end
  end

  memoize def closed_alerts_count
    ActiveRecord::Base.connected_to(role: :reading) do
      base_repository_alerts_scope.dismissed.count
    end
  end

  memoize def base_repository_alerts_scope
    if logged_in?
      RepositoryVulnerabilityAlert.
        has_vulnerable_version_range.
        where(vulnerability_id: advisory.id, repository_id: dependabot_alerts_query.repository_ids)
    else
      RepositoryVulnerabilityAlert.none
    end
  end

  memoize def repository_alerts_scope
    ActiveRecord::Base.connected_to(role: :reading) do
      scope = base_repository_alerts_scope
      scope = show_closed_alerts? ? scope.dismissed : scope.open
      scope = dependabot_alerts_query.apply_sort(scope)
      paginated_scope = scope.paginate(per_page: PER_PAGE, page: current_page)
      paginated_scope.total_entries = show_closed_alerts? ? closed_alerts_count : open_alerts_count
      paginated_scope
    end
  end

  memoize def advisory
    ghsa_id = AdvisoryDB.canonical_case_for_ghsa_id(params[:id])
    Vulnerability.find_by(ghsa_id: ghsa_id)
  end

  # Advisories are public

  # CAP bypass is fine here as advisories are public.
  def target_for_conditional_access
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  def ip_allowlist_enforceable
    :no
  end

  def external_conditional_access_policy_enforceable
    :no
  end

  # This overrides a setting that was prevent us from routing to the advisories page because
  # it was expecting an SAML SSO target event though we don't need to have one for now
  def require_active_external_identity_session?
    false
  end

  def two_factor_enforceable
    :no
  end

  def require_advisory
    render_404 unless advisory&.readable_by?(current_user)
  end

  # Unauthenticated and Authenticated: 60 searches every minute
  def search_rate_limit_max
    60
  end

  def anonymous_search_identifier
    ja3_hash = request.env.fetch("HTTP_X_SSL_JA3_HASH", nil)
    return ja3_hash if ja3_hash.present?
    request.remote_ip
  end

  def search_rate_limit_key
    "advisories_search_limiter:#{logged_in? ? current_user.id : anonymous_search_identifier}"
  end

  def search_rate_limit_record
    GitHub.dogstats.increment("global_advisories.ratelimited", { tags: ["query_present:#{params[:query].present?}", "logged_in:#{logged_in?}"] })
  end

  def vulnerability_query
    Search::QueryHelper.new(parsed_query, "Vulnerabilities",
      current_user: current_user,
      remote_ip: request.remote_ip,
      page: current_page,
      per_page: PER_PAGE,
      user_session: user_session
    ).vulnerability_query
  end

  memoize def vulnerability_ecosystem_aggregation_results
    Search::QueryHelper.new("", "Vulnerabilities",
      aggregations: :ecosystem,
      current_user: current_user,
      remote_ip: request.remote_ip,
      per_page: 0,
      user_session: user_session
    ).vulnerability_query.execute
  end

  def reviewed_advisory_count
    vulnerability_ecosystem_aggregation_results.total
  end

  memoize def ecosystem_counts
    aggregations = vulnerability_ecosystem_aggregation_results.aggregations

    buckets = aggregations&.dig("ecosystem", "buckets") || {}
    buckets.reduce({}) do |output, value|
      output.merge(value["key"] => value["doc_count"])
    end
  end

  memoize def unreviewed_advisory_count
    query = Search::QueryHelper.new("type:unreviewed", "Vulnerabilities",
      current_user: current_user,
      remote_ip: request.remote_ip,
      per_page: 0,
      user_session: user_session
    ).vulnerability_query

    query.execute.total
  end

  def org_ids_to_exclude
    cap_filter.unauthorized_resource_ids(current_user.organizations) if logged_in?
  end

  memoize def dependabot_alerts_query
    Search::Queries::DependabotAlertsQuery.new(
      query: params[:query],
      current_user: current_user,
      org_ids_to_exclude: org_ids_to_exclude,
    )
  end

  # Marks advisory as read across all repositories affected by advisory
  # that the user has access to; regardless of organization.
  # This ensures that once user has seen the advisory's dependabot alerts page
  # (which shows all the affected repositories across organizations), we can safely
  # mark all web notification threads on the advisory for the given user as read.
  def mark_threads_as_read
    authorized_repo_ids = repository_alerts_scope.map(&:repository_id).uniq
    owner_ids = Repository.where(id: authorized_repo_ids).distinct.pluck(:owner_id)

    if dependabot_alerts_query.owner_ids
      owner_ids += dependabot_alerts_query.owner_ids
    end

    User.where(id: owner_ids).each do |owner|
      thread = advisory.becomes(SecurityAdvisory)
      thread.notifications_list = owner
      # TODO(abeaumont): This cannot be made async directly as a SecurityAdvisory
      # doesn't have a notification list and it's added on demand.
      # Our current async mark process doesn't support this.
      mark_thread_as_read thread
    end
  end
end
