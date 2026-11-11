# typed: true
# frozen_string_literal: true

class Stafftools::Users::Securities::HistoriesController < StafftoolsController
  before_action :ensure_user_exists

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  def show
    keys = %w{actor_id user_id}
    keys << "org_id" if this_user.organization?
    query =
      if GitHub.driftwood_ade_queries_enabled?
        <<~KQL
          webevents
          | where #{keys.reverse.map { |k| "#{k} == #{this_user.id}" }.join(" or ")}
        KQL
      else
        keys.reverse.map { |k| "#{k}:#{this_user.id}" }.join " OR "
      end

    redirect_to stafftools_audit_log_path(query: query)
  end
end
