# typed: true
# frozen_string_literal: true

class InnersourceAdvisoriesController < ApplicationController
  before_action :login_required
  before_action :require_advisory

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Notify,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Configurations,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Notify,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::Authnd,
    only: [:dependabot_alerts]

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
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    only: [:organization_filter]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Notify,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Spokes,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    only: [:history]

  PER_PAGE = 25

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

  def history # rubocop:todo GitHub/UseRestfulActions
    render partial: "global_advisories/history", locals: {
      view: create_view_model(GlobalAdvisories::HistoryView, advisory: advisory)
    }
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

  def organization_filter # rubocop:todo GitHub/UseRestfulActions
    render partial: "global_advisories/organization_filter", locals: {
      view: create_view_model(GlobalAdvisories::ShowView, query: dependabot_alerts_query, advisory: advisory)
    }
  end

  private

  memoize def advisory
    return nil unless current_user

    ghsa_id = AdvisoryDB.canonical_case_for_ghsa_id(params[:id])
    Vulnerability.visible_to(current_user.business_ids, current_user.organization_ids)
      .find_by(ghsa_id: ghsa_id)
  end

  memoize def base_repository_alerts_scope
    RepositoryVulnerabilityAlert.
      has_vulnerable_version_range.
      where(vulnerability_id: advisory.id, repository_id: dependabot_alerts_query.repository_ids)
  end

  memoize def dependabot_alerts_query
    Search::Queries::DependabotAlertsQuery.new(
      query: params[:query],
      current_user: current_user,
      org_ids_to_exclude: [],
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

  def mark_threads_as_read
    authorized_repo_ids = repository_alerts_scope.map(&:repository_id).uniq
    owner_ids = Repository.where(id: authorized_repo_ids).distinct.pluck(:owner_id)

    if dependabot_alerts_query.owner_ids
      owner_ids += dependabot_alerts_query.owner_ids
    end

    User.where(id: owner_ids).each do |owner|
      thread = advisory.becomes(SecurityAdvisory)
      thread.notifications_list = owner
      mark_thread_as_read thread
    end
  end

  def require_advisory
    render_404 unless advisory&.readable_by?(current_user) && innersource_authorized?(advisory)
  end

  # Checks that the owning business/org is authorized for innersource advisories
  # (feature flag + GHAS purchase). This is an entry-point check — the model-level
  # readable_by? only verifies membership.
  def innersource_authorized?(vuln)
    owner = vuln.owner
    case owner
    when Business
      AdvisoryDB::Innersource.business_authorized?(business: owner)
    when Organization
      AdvisoryDB::Innersource.org_authorized?(org: owner)
    else
      false
    end
  end

  # CAP enforcement: the advisory's owning business or org is the resource/target.
  # resource_for_conditional_access is the preferred CAP method per the CAP cookbook.
  def resource_for_conditional_access
    return :no_resource_for_conditional_access unless advisory # rubocop:disable GitHub/SpecifyResourceForConditionalAccess

    advisory.owner
  end

  def target_for_conditional_access
    resource_for_conditional_access
  end
end
