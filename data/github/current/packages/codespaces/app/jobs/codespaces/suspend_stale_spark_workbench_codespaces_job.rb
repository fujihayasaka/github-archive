# typed: true
# frozen_string_literal: true

module Codespaces
  class SuspendStaleSparkWorkbenchCodespacesJob < CodespacesJob
    schedule interval: 5.minutes, condition: -> { !GitHub.enterprise? }

    BATCH_SIZE = 50
    STALE_THRESHOLD = 30.minutes

    locked_by timeout: 10.minutes, key: DEFAULT_LOCK_PROC

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    def perform
      # Candidate codespaces are those that are consuming_compute?, which is state stored in the environment_data JSON column. Use
      # JSON_EXTRACT to find candidates in a state we may need to suspend.
      active_codespaces = Codespace.where("last_used_at < ? AND environment_data->'$.state' IN (?)", STALE_THRESHOLD.ago, Codespaces::Vscs::State::CONSUMING_COMPUTE_STATES)

      active_spark_codespaces = active_codespaces.only_workbench_cloud_environments.pluck(Arel.sql("JSON_VALUE(linked_resources, '$.spark_workbench_id'), id"))
      codespace_ids_by_workbench_uuid = Hash[active_spark_codespaces]

      codespace_ids_by_workbench_uuid.keys.each_slice(BATCH_SIZE) do |workbench_uuids|
        spark_workbenches = Spark::Workbench.for_uuid_strings(workbench_uuids)

        users_by_id = User.where(id: spark_workbenches.map(&:user_id).uniq).index_by(&:id)

        workbench_uuids_by_workbench_id = spark_workbenches.each_with_object({}) do |workbench, hash|
          hash[workbench.id] = workbench.uuid_string
        end
        workbench_ids = workbench_uuids_by_workbench_id.keys

        # Temporarily joining to the workbench table to get the user_id for feature flag check
        recent_iterations = Spark::WorkbenchIteration.where(spark_workbench_id: workbench_ids).joins(:workbench).group(:spark_workbench_id).pluck("spark_workbench_id, user_id, MAX(spark_workbench_iterations.created_at)")

        # Add workbenches that have no iteration records yet
        recent_iteration_workbench_ids = recent_iterations.map(&:first)
        recent_iterations += spark_workbenches.filter_map do |workbench|
          [workbench.id, workbench.user_id, nil] unless recent_iteration_workbench_ids.include?(workbench.id)
        end

        # While this is feature flagged, report the total number of stale sessions detected separate from the number
        # we'll actually suspend.
        total_stale_count = recent_iterations.count { |_, _, last_iteration_ts| last_iteration_ts.nil? || last_iteration_ts < STALE_THRESHOLD.ago }
        GitHub.dogstats.count("codespaces.stale_spark_workbench.count", total_stale_count)

        stale_spark_codespace_ids = recent_iterations.filter_map do |workbench_id, user_id, last_iteration_ts|
          next unless user = users_by_id[user_id]
          workbench_uuid = workbench_uuids_by_workbench_id[workbench_id]

          copilot_user = Copilot::Public::User.new(user)
          user_has_prus_remaining = copilot_user.quota_percentage_remaining(feature: "premium_interactions") > 0
          user_has_dev_compute_remaining = Codespaces::Access::SparkWorkbenchUsageChecker.new(user).perform.allowed?

          GitHub.logger.info(
            "Detected stale Spark codespace",
            "code.namespace" => self.class.name,
            "gh.user.id" => user_id,
            "user_has_prus_remaining" => user_has_prus_remaining,
            "user_has_dev_compute_remaining" => user_has_dev_compute_remaining,
            "spark_workbench_id" => workbench_uuid,
            "last_iteration_ts" => last_iteration_ts,
          )

          # Don't suspend if the user has PRUs and dev compute remaining.
          next if user_has_prus_remaining && user_has_dev_compute_remaining

          codespace_ids_by_workbench_uuid[workbench_uuid] if last_iteration_ts.nil? || last_iteration_ts < STALE_THRESHOLD.ago
        end

        GitHub.dogstats.count("codespaces.stale_spark_workbench_suspended.count", stale_spark_codespace_ids.size)
        Codespace.where(id: stale_spark_codespace_ids).each do |codespace|
          CodespacesSuspendEnvironmentJob.perform_later(codespace: codespace)
        end
      end
    end
  end
end
