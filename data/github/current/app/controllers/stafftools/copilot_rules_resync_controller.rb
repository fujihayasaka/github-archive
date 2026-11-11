# typed: strict
# frozen_string_literal: true

class Stafftools::CopilotRulesResyncController < StafftoolsController
  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    only: [:index]

  before_action :dotcom_required

  sig { void }
  def index
    if FeatureFlag.vexi.enabled?(:stafftools_copilot_rules_resync, default: false)
      render "stafftools/copilot_rules_resync/index"
    else
      render_404
    end
  end

  sig { void }
  def create
    unless FeatureFlag.vexi.enabled?(:stafftools_copilot_rules_resync, default: false)
      render_404
      return
    end

    reason = params[:reason].to_s.strip

    if reason.blank?
      flash[:error] = "Reason is required"
      redirect_to stafftools_copilot_rules_resync_index_path
    else
      begin
        instrument("staff.copilot_rules_resync_triggered", { reason: reason })

        Copilot::BatchUpdateAllEnterpriseOrgSettingsJob.perform_later

        redirect_to stafftools_copilot_rules_resync_index_path,
          notice: "Resync job enqueued."
      rescue StandardError => e
        flash[:error] = "Failed to enqueue resync job: #{e.message}"
        redirect_to stafftools_copilot_rules_resync_index_path
      end
    end
  end
end
