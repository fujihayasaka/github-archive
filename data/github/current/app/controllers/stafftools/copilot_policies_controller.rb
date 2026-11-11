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
    }
  end

  # Bump the policy cache version
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

  # Set the cache refresh interval
  sig { void }
  def update
    reason = params[:reason].to_s.strip
    value = params[:value].to_s.strip
    unit = params[:unit].to_s.strip

    if reason.blank?
      redirect_to stafftools_copilot_policies_path, alert: "Reason is required" and return
    end

    numeric_value = Integer(value, 10) rescue nil
    if numeric_value.nil? || numeric_value <= 0
      redirect_to stafftools_copilot_policies_path,
        alert: "Interval value must be a positive integer" and return
    end

    multiplier =
      case unit
      when "minutes" then 60
      when "hours" then 3600
      end

    if multiplier.nil?
      redirect_to stafftools_copilot_policies_path,
        alert: "Unit must be 'minutes' or 'hours'" and return
    end

    seconds = T.must(numeric_value) * T.must(multiplier)

    begin
      new_interval = Copilot::CacheRefreshIntervalSetting.set!(
        seconds: seconds,
        actor: current_user,
        reason: reason
      )

      instrument("staff.copilot_cache_refresh_interval_updated", {
        new_seconds: new_interval.to_i,
        reason: reason,
      })

      redirect_to stafftools_copilot_policies_path,
        notice: "Cache refresh interval set to #{new_interval.inspect}."
    rescue StandardError => e
      redirect_to stafftools_copilot_policies_path,
        alert: "Failed to update cache refresh interval: #{e.message}"
    end
  end
end
