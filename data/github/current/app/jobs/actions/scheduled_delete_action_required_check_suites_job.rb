# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: false
# frozen_string_literal: true

module Actions
  class ScheduledDeleteActionRequiredCheckSuitesJob < ApplicationJob
    schedule interval: 5.minutes, condition: -> { !GitHub.enterprise? }

    queue_as :delete_action_required_check_suites

    retry_on_dirty_exit

    def perform
      num_days = 30
      window_in_mins = 15
      limit = 5000

      app_ids = [GitHub.launch_github_app.id, GitHub.launch_lab_github_app&.id].compact

      stat = "actions.scheduled_delete_action_required_check_suite_job"
      results = []
      GitHub.dogstats.time "#{stat}.query_time" do
        bindings = {
          conclusion: CheckSuite.conclusions[:action_required],
          num_days: num_days,
          window_in_mins: window_in_mins,
          app_ids: app_ids,
          limit: Arel.sql(limit.to_s)
        }

        sql = Arel.sql(<<~SQL, **bindings)
            /* cross-shard-query-exempted-permanent */
            SELECT id, repository_id, github_app_id
            FROM check_suites
            WHERE conclusion = :conclusion
              AND event IN ('pull_request', 'pull_request_review_comment', 'pull_request_review')
              AND created_at BETWEEN (NOW() - interval :num_days day - interval :window_in_mins minute) AND (NOW() - interval :num_days day)
              AND github_app_id IN (:app_ids)
            ORDER BY id DESC
            LIMIT :limit
        SQL

        results = CheckSuite.connection.select_rows(sql)
      end
      GitHub.dogstats.count("#{stat}.ids_count", results.size)

      results.each do |check_suite_id, repository_id, github_app_id|
        Actions::DeleteActionRequiredCheckSuiteJob.perform_later(check_suite_id, repository_id, github_app_id)
      end
    end
  end
end
