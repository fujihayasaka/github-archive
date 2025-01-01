# typed: true
# frozen_string_literal: true

class Stafftools::Users::AbuseReportsController < StafftoolsController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  ABUSE_REPORTS_PER_PAGE = 50

  include Stafftools::Users::ControllerLayoutMethods
  before_action :ensure_user_exists

  layout :overview_layout

  def index
    return render_404 unless GitHub.user_abuse_mitigation_enabled?
    return render_404 unless this_user.present?

    abuse_reports = this_user.received_abuse_reports
                        .order("created_at DESC")
                        .simple_paginate(
                          per_page: ABUSE_REPORTS_PER_PAGE,
                          page: params[:page].to_i
                        )
    total_count = this_user.received_abuse_reports.count
    render "stafftools/users/abuse_reports/index", locals: { user: this_user, abuse_reports: abuse_reports, total_count: total_count }
  end
end
