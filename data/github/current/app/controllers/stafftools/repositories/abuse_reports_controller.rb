# typed: true
# frozen_string_literal: true

class Stafftools::Repositories::AbuseReportsController < StafftoolsController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:abuse_reports]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:abuse_reports],
    optional: true

  ABUSE_REPORTS_PER_PAGE = 50

  before_action :ensure_repo_exists

  javascript_bundle :"stafftools-repositories"
  layout "layouts/stafftools/repository/collaboration"

  def abuse_reports # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless GitHub.can_report?
    return render_404 unless current_repository.present?

    scope = AbuseReport.for_repository_maintainer(current_repository.id)
    abuse_reports = GitHub::SimplePagination.paginate_collection(
      scope.order("created_at DESC"),
      per_page: ABUSE_REPORTS_PER_PAGE,
      page: params[:page].to_i
    )

    render "stafftools/repositories/abuse_reports",
      locals: {
        user: current_user,
        current_repository: current_repository,
        total_count: scope.count,
        abuse_reports: abuse_reports,
        report_content_enabled: current_repository.tiered_reporting_explicitly_enabled?
      }
  end
end
