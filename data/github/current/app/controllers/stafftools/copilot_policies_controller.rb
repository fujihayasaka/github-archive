# typed: true
# frozen_string_literal: true

class Stafftools::CopilotPoliciesController < StafftoolsController

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
    render "stafftools/copilot_policies/index", locals: {
      current_version: Copilot::PolicyCacheVersion.current_version,
      minimum_version: Copilot::PolicyCacheVersion.minimum_version,
      stored_version: Copilot::PolicyCacheVersion.stored_version,
      dynamic_enabled: Copilot::PolicyCacheVersion.dynamic_version_enabled?,
    }
  end

  sig { void }
  def create
    reason = params[:reason].to_s.strip

    if reason.blank?
      redirect_to stafftools_copilot_policies_path, alert: "Reason is required" and return
    end

    begin
      new_version = Copilot::PolicyCacheVersion.bump!(
        actor: current_user,
        reason: reason
      )

      instrument("staff.copilot_policy_cache_bumped", {
        new_version: new_version,
        reason: reason,
      })

      redirect_to stafftools_copilot_policies_path,
        notice: "Policy cache version bumped to #{new_version}. All user caches will be invalidated."
    rescue StandardError => e
      redirect_to stafftools_copilot_policies_path,
        alert: "Failed to bump cache version: #{e.message}"
    end
  end
end
