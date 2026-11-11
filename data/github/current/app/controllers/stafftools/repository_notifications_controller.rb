# typed: true
# frozen_string_literal: true

class Stafftools::RepositoryNotificationsController < StafftoolsController

  before_action :ensure_repo_exists

  layout "layouts/stafftools/repository/collaboration"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def index
    audit_log_query = [
      "data.name:Email",
      "data.hook_type:repo",
      "repo_id:#{current_repository.id}",
    ].join(" AND ")

    if GitHub.driftwood_ade_queries_enabled?
      audit_log_query = <<~KQL
        webevents
        | where data.name == "Email" and data.hook_type == "repo" and repo_id == #{current_repository.id}
      KQL
    end

    view = Stafftools::RepositoryViews::RepositoryNotificationsView.new(
      current_repository: current_repository,
      audit_log_data: fetch_audit_log_teaser(audit_log_query),
    )

    render "stafftools/repository_notifications/index", locals: {
      view: view,
    }
  end
end
