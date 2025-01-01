# typed: strict
# frozen_string_literal: true

class Stafftools::CopilotMetricSummariesController < StafftoolsController
  layout "layouts/stafftools/user/content"

  before_action :dotcom_required
  before_action :ensure_user_exists

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    ApplicationRecord::Collab,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:show]

  sig { void }
  def show
    if this_user.organization?
      summaries = Copilot::MetricSummary.where(owner: this_user).order(start_date: :desc)

      render "stafftools/copilot_metric_summaries/show", locals: { summaries: summaries }
    else
      redirect_to(stafftools_user_copilot_settings_path(this_user))
    end
  end

  sig { void }
  def update
    if this_user.organization?
      dates = []
      1.upto(13).each do |i|
        date = Date.current.beginning_of_week(:monday) - i.weeks
        Copilot::Metrics::SummaryJob.perform_later(owner_id: this_user.id, start_date: date.to_s)
      end

      redirect_to(stafftools_user_copilot_metric_summaries_path(this_user),
        notice: "Metric summaries have been queued. This may take a few minutes to complete.")
    else
      redirect_to(stafftools_user_copilot_settings_path(this_user))
    end
  end

  sig { void }
  def recalculate_all # rubocop:todo GitHub/UseRestfulActions
    if this_user.organization?
      Copilot::Metrics::BatchedSummaryJob.perform_backfill

      redirect_to(stafftools_user_copilot_metric_summaries_path(this_user),
        notice: "Metric summaries have been queued. This will take several hours to complete. Check the datadog dashboard for progress.")
    else
      redirect_to(stafftools_user_copilot_settings_path(this_user))
    end
  end
end
