# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class CheckRuns < Platform::Loader
      include Scientist

      def self.load(repository, sha)
        self.for(repository).load(sha)
      end

      def initialize(repository)
        @repository = repository
      end

      def fetch(oids)
        bindings = {
          head_shas:  oids,
          repository_id: @repository.id,
        }

        sql = Arel.sql(raw_sql, **bindings)
        records_by_sha = CheckRun.connection.select_all(sql).to_a.group_by { |result| result["head_sha"] }

        result = records_by_sha.transform_values do |records|
          records.map { |record| CheckRun.send(:instantiate, record) }
        end
        result.default = [].freeze
        result
      end

      private

      def compare_for_experiment(hash)
        # The structure is like this: {"sha": [check_run_hashes]} but we don't care about the order in which check runs are queried
        hash.map { |k, v| [k, v.map { |r| r["id"] }.sort] }.to_h
      end

      def check_run_select
        columns = CheckRun.column_names - Platform::Loaders::CheckRunText::SUPPORTED_COLUMNS.map(&:to_s)
        columns.map { |col| "check_runs.#{col}" }.join(", ")
      end

      def raw_sql
        <<~SQL
          SELECT #{check_run_select},
                check_suites.head_sha
          FROM check_runs
          INNER JOIN check_suites
            ON check_suites.id = check_runs.check_suite_id
          WHERE check_runs.repository_id = :repository_id
          AND check_runs.id IN (
            SELECT * FROM (
              SELECT MAX(check_runs.id) as id
              FROM check_runs
              JOIN check_suites ON check_suites.id = check_runs.check_suite_id
              WHERE check_suites.repository_id = :repository_id
              AND check_suites.head_sha IN (:head_shas)
              AND check_suites.hidden = FALSE
              AND (check_suites.workflow_file_path IS NULL OR check_runs.created_at >= IFNULL(check_suites.started_at, check_suites.created_at))
              GROUP BY check_runs.check_suite_id, check_runs.name
            ) AS subquery
          )
        SQL
      end
    end
  end
end
