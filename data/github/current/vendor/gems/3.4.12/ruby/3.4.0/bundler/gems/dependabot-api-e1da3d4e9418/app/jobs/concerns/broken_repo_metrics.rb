# frozen_string_literal: true

# This module handles broken repository metric emission
module BrokenRepoMetrics
  extend ActiveSupport::Concern

  private

  def emit_compute_reduction_metric(update_config, errors)
    return unless errors.size.positive?

    if update_config.dependency_groups.any?
      emit_grouped_compute_reduction_metric(update_config)
    else
      MetricsClient.increment("compute_reduction", tags: { initiative: "pause_on_broken_repos" })
    end
  end

  def emit_grouped_compute_reduction_metric(update_config)
    group_count = update_config.dependency_groups.count
    group_names = update_config.dependency_groups.limit(10).pluck(:name).join(",")

    MetricsClient.increment("compute_reduction", tags: {
                              initiative: "pause_on_broken_repos",
                              grouped_update: true,
                              group_count: group_count,
                              group_names: group_names,
                            })
  end

  def log_broken_repo(update_config, errors)
    if update_config.dependency_groups.any?
      log_grouped_broken_repo(update_config, errors)
    else
      log_individual_broken_repo(errors)
    end

    log_broken_repo_message(update_config, errors)
  end

  def log_grouped_broken_repo(update_config, errors)
    group_count = update_config.dependency_groups.count
    group_names = update_config.dependency_groups.limit(10).pluck(:name).join(",")
    error_type = errors&.first || "unknown"

    MetricsClient.increment("grouped_update.config_broken", tags: {
                              grouped_update: true,
                              group_count: group_count,
                              group_names: group_names,
                              error_type: error_type,
                            })

    MetricsClient.increment("broken_update", tags: {
                              error_type: error_type,
                              grouped_update: true,
                              group_count: group_count,
                              group_names: group_names,
                            })
  end

  def log_individual_broken_repo(errors)
    error_type = errors&.first || "unknown"
    MetricsClient.increment("broken_update", tags: { error_type: error_type })
  end

  def log_broken_repo_message(update_config, errors)
    Dependabot::Logger.info(
      msg: "Broken Repository",
      "code.namespace": "CreateScheduledUpdateJob",
      "gh.dependabot_api.update_config.id": update_config.id,
      repo_id: update_config.repo_id,
      errors: errors&.join(",") || "unknown"
    )
  end
end
