# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class CombinedStatusOverview < Platform::Loader
      include Scientist

      def self.load(repository, sha)
        self.for(repository).load(sha)
      end

      def initialize(repository)
        @repository = repository
      end

      def fetch(oids)
        bindings = { head_shas: oids, repository_id: @repository.id }

        check_suite_ids = T.let([], T.untyped)

        check_suite_ids = CheckSuite.connection.select_values(Arel.sql(latest_check_suite_ids_for_shas_and_repository, **bindings))

        if check_suite_ids.length > 0
          bindings[:check_suite_ids] = check_suite_ids
          hash_results = CheckRun.connection.select_all(Arel.sql(check_runs_new_sql, **bindings)).to_a
        else
          ## return an empty array; these check suites have been deleted as per our retention policy
          hash_results = []
        end

        hash_results.each do |row|
          row["conclusion"] = CheckRun::conclusions.key(row["conclusion"])
        end

        # We could do a raw SQL here too, but the implementation is complex enough and did want to keep it as DRY as possible
        statuses = ::Statuses::Service.current_for_shas(repository_id: @repository.id, shas: oids)
        hash_results += statuses.map do |status|
          {}.tap do |h|
            h["total"] = 1
            h["conclusion"] = status.state
            h["sha"] = status.sha
          end
        end

        records_by_sha = hash_results.group_by { |result| result["sha"] }

        records_by_sha.default = [default]
        records_by_sha
      end

      def default
        {}.tap do |h|
          h["total"] = 0
          h["conclusion"] = nil
        end
      end

      def self.short_text(rows)
        total_count = rows.inject(0) { |sum, x| sum + x["total"] }
        return nil if total_count == 0

        successful_count = rows.inject(0) { |sum, x| sum + (x["conclusion"] == "success" ? x["total"] : 0) }
        "#{successful_count} / #{total_count} checks OK"
      end

      private

      def latest_check_suite_ids_for_shas_and_repository
        <<-SQL
          SELECT MAX(check_suites.id)
            FROM check_suites FORCE INDEX (index_check_suites_on_head_sha_and_repository_id)
            WHERE check_suites.head_sha IN (:head_shas)
              AND check_suites.repository_id = :repository_id
              AND check_suites.hidden = FALSE
              AND check_suites.workflow_file_path IS NOT NULL
            GROUP BY check_suites.github_app_id, check_suites.workflow_file_path, check_suites.event, check_suites.head_sha

          UNION ALL

          SELECT check_suites.id
            FROM check_suites FORCE INDEX (index_check_suites_on_head_sha_and_repository_id)
            WHERE check_suites.head_sha IN (:head_shas)
              AND check_suites.repository_id = :repository_id
              AND check_suites.workflow_file_path IS NULL
        SQL
      end

      def check_runs_new_sql
        <<~SQL
          SELECT COUNT(*) AS total, check_runs.conclusion, check_suites.head_sha AS sha
          FROM check_runs
          JOIN check_suites
            ON check_suites.id = check_runs.check_suite_id
            AND check_suites.repository_id = check_runs.repository_id
          WHERE check_runs.id IN (
            SELECT id FROM (
              SELECT MAX(check_runs.id) as id
              FROM check_runs
              JOIN check_suites ON check_suites.id = check_runs.check_suite_id AND check_suites.repository_id = check_runs.repository_id
              WHERE check_suites.id IN (:check_suite_ids)
              AND check_runs.repository_id = :repository_id
              AND (check_suites.workflow_file_path IS NULL OR check_runs.created_at >= IFNULL(check_suites.started_at, check_suites.created_at))
              GROUP BY check_runs.check_suite_id, check_runs.name
            ) AS subquery
          )
          AND check_runs.repository_id = :repository_id
          GROUP BY check_runs.conclusion, check_suites.head_sha
        SQL
      end
    end
  end
end
