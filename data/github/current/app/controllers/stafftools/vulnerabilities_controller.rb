# typed: true
# frozen_string_literal: true

module Stafftools
  class VulnerabilitiesController < StafftoolsController
    before_action :ghe_content_analysis_required

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Collab,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Repositories,
      only: [:index]

    depends_on_clusters ApplicationRecord::Copilot,
      only: [:index], optional: true

    def index
      last_synced_at = EnterpriseAdvisoryDatabaseSyncJob.last_run_at
      sync_data = {
        last_synced_at: last_synced_at,
        show: last_synced_at.present?,
      }

      render "stafftools/vulnerabilities/index", locals: {
        sync_data: sync_data,
      }
    end

    def enqueue_dotcom_sync # rubocop:todo GitHub/UseRestfulActions
      return render_404 unless GitHub.ghe_content_analysis_enabled?
      EnterpriseAdvisoryDatabaseSyncJob.perform_later(force_all: true)
      flash[:notice] = "Vulnerability sync job enqueued ..."
      redirect_to :back
    end

    private

    def ghe_content_analysis_required
      render_404 and return unless GitHub.ghe_content_analysis_enabled?
    end
  end
end
