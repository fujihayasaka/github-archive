# typed: strict
# frozen_string_literal: true

class Copilot::Spark::ThrottleStatusController < Copilot::Workbench::AbstractWorkbenchController
  include ApplicationController::VerifiedFetchDependency

  allow_verified_fetch

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:index]

  # Default threshold when no feature flag is enabled
  DEFAULT_RATE_LIMIT_REPORTS_THRESHOLD = 100

  # Available threshold options via feature flags
  THRESHOLD_OPTIONS = T.let({
    "spark_model_rate_limit_50" => 50,
    "spark_model_rate_limit_200" => 200,
    "spark_model_rate_limit_500" => 500,
  }.freeze, T::Hash[String, Integer])

  # Time window in minutes for checking rate limit reports
  SLIDING_WINDOW_MINUTES = 5

  # Cache key for throttle status
  RATE_LIMIT_COUNT_CACHE_KEY = "spark:rate_limit_count"

  sig { void }
  def index
    current_threshold = rate_limit_threshold
    globally_throttled = globally_throttled?
    rate_limit_reports_count = cached_rate_limit_reports_count

    if globally_throttled
      GitHub.logger.info(
        "code.namespace": "Copilot::Spark::ThrottleStatusController",
        "current_threshold": current_threshold,
        "throttled": globally_throttled,
        "window_minutes": SLIDING_WINDOW_MINUTES,
        "rate_limit_reports_count": rate_limit_reports_count,
      )
    end

    respond_to do |format|
      format.json do
        render json: {
          throttled: globally_throttled,
          threshold: current_threshold,
          window_minutes: SLIDING_WINDOW_MINUTES,
          rate_limit_reports_count: rate_limit_reports_count,
        }
      end
    end
  end

  private

  sig { returns(T::Boolean) }
  def globally_throttled?
    return false unless feature_enabled_for_current_user?(feature_name: :spark_log_rate_limit_event)

    cached_rate_limit_reports_count >= rate_limit_threshold
  end

  sig { returns(Integer) }
  def rate_limit_threshold
    THRESHOLD_OPTIONS.each do |flag_name, threshold|
      return threshold if current_user&.feature_flag_enabled?(flag_name, default: false)
    end
    DEFAULT_RATE_LIMIT_REPORTS_THRESHOLD
  end

  sig { returns(Integer) }
  def cached_rate_limit_reports_count
    GitHub.cache.fetch(RATE_LIMIT_COUNT_CACHE_KEY, ttl: 30.seconds) do
      check_rate_limit_reports_count
    end
  end

  sig { returns(Integer) }
  def check_rate_limit_reports_count
    time_threshold = SLIDING_WINDOW_MINUTES.minutes.ago
    rate_limit_count = Spark::ModelRateLimit.where("created_at >= ?", time_threshold).count

    GitHub.logger.info(
      "code.namespace": "Copilot::Spark::ThrottleStatusController",
      "rate_limit_reports_count": rate_limit_count,
    )

    rate_limit_count
  end
end
