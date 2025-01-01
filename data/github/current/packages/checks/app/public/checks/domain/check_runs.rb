# typed: strict
# frozen_string_literal: true

module Checks
  class Domain
    class CheckRuns < GH::Domain::Base
      # Get the IDs of the latest CheckRuns for the check suite and repository on the given head SHA.
      #
      # @param repository_id The Repository ID to scope to.
      # @param check_suite_id The CheckSuite ID to scope to.
      # @param head_sha The head SHA to scope to.
      # @param latest_check_suite_run_only Whether to return only the CheckRuns created after the start of the check
      # suite. This is relevant in the case of re-runs where false would mean the returned CheckRuns could include the
      # CheckRuns from the previous check suite run.
      # @return The IDs for the CheckRuns
      sig do
        params(repository_id: Integer, check_suite_id: Integer, head_sha: String, latest_check_suite_run_only: T::Boolean).
        returns(T::Array[Integer]).
        checked(:always).
        on_failure(:raise)
      end
      def latest_ids(repository_id:, check_suite_id:, head_sha:, latest_check_suite_run_only:)
        ids = fetch_latest_ids(
          repository_id:,
          check_suite_id:,
          head_sha:,
          latest_check_suite_run_only:,
        )

        GitHub.logger.info(
          "code.namespace" => self.class.name,
          "code.function" => __method__,
          "gh.repository.id" => repository_id,
          "gh.repository.head_sha" => head_sha,
          "gh.actions.check_suite.id" => check_suite_id,
          "gh.actions.check_runs.size" => ids.size,
        )

        ids
      end

      # Get the IDs of the latest CheckRuns for the check suite.
      #
      # @param check_suite The check suite to scope to.
      # @return The IDs for the CheckRuns
      sig do
        params(check_suite: ICheckSuite).
        returns(T::Array[Integer]).
        checked(:always).
        on_failure(:raise)
      end
      def latest_ids_for_check_suite(check_suite)
        ids = fetch_latest_ids(
          repository_id: check_suite.repository_id,
          check_suite_id: check_suite.id,
          head_sha: check_suite.head_sha,
          latest_check_suite_run_only: check_suite.actions_app?,
        )

        created_at_bucket = created_at_bucket(check_suite.created_at)
        GitHub.dogstats.increment("actions.checks.domain.check_runs.latest_ids_for_check_suite.created_at", tags: ["bucket:#{created_at_bucket}"])
        GitHub.logger.info(
          "code.namespace" => self.class.name,
          "code.function" => __method__,
          "gh.repository.id" => check_suite.repository_id,
          "gh.repository.head_sha" => check_suite.head_sha,
          "gh.actions.check_suite.id" => check_suite.id,
          "gh.actions.check_suite.created_at_bucket" => created_at_bucket,
          "gh.actions.check_runs.size" => ids.size,
        )

        ids
      end

      # Get the latest CheckRuns for the check suite.
      #
      # TODO: Predicates to support:
      # - status
      # - NOT status
      # - name OR display_name
      # - conclusion
      # - for_app_id (join with check_suites)
      #
      # @param check_suite The check suite to scope to.
      # @param first_only Whether to get only the first CheckRun.
      # @return The latest CheckRuns for the given check suite.
      # rubocop:disable Metrics/MethodLength
      sig do
        params(check_suite: ICheckSuite, first_only: T::Boolean).
        returns(T::Array[CheckRun]).
        checked(:always).
        on_failure(:raise)
      end
      def latest_for_check_suite(check_suite, first_only: false)
        ActiveRecord::Base.connected_to(role: :reading) do
          relation = latest_relation(
            repository_id: check_suite.repository_id,
            check_suite_id: check_suite.id,
            head_sha: check_suite.head_sha,
            latest_check_suite_run_only: check_suite.actions_app?
          )

          if first_only
            relation = relation.order(id: :asc).limit(1)
          end

          results = relation.to_a

          created_at_bucket = created_at_bucket(check_suite.created_at)
          GitHub.dogstats.increment("actions.checks.domain.check_runs.latest_for_check_suite.created_at", tags: ["bucket:#{created_at_bucket}"])
          GitHub.logger.info(
            "code.namespace" => self.class.name,
            "code.function" => __method__,
            "gh.repository.id" => check_suite.repository_id,
            "gh.repository.head_sha" => check_suite.head_sha,
            "gh.actions.check_suite.id" => check_suite.id,
            "gh.actions.check_suite.created_at_bucket" => created_at_bucket,
            "gh.actions.check_runs.size" => results.size,
          )

          results
        end
      end

      private

      sig do
        params(repository_id: Integer, check_suite_id: Integer, head_sha: String, latest_check_suite_run_only: T::Boolean).
        returns(ActiveRecord::Relation).
        checked(:always).
        on_failure(:raise)
      end
      def latest_relation(repository_id:, check_suite_id:, head_sha:, latest_check_suite_run_only:)
        latest_check_run_ids = latest_ids(repository_id:, check_suite_id:, head_sha:, latest_check_suite_run_only:)
        return CheckRun.none if latest_check_run_ids.empty?

        CheckRun.annotate("cross-shard-query-exempted").where(id: latest_check_run_ids)
      end

      sig do
        params(repository_id: Integer, check_suite_id: Integer, head_sha: String, latest_check_suite_run_only: T::Boolean).
        returns(T::Array[Integer]).
        checked(:always).
        on_failure(:raise)
      end
      def fetch_latest_ids(repository_id:, check_suite_id:, head_sha:, latest_check_suite_run_only:)
        sql = Arel.sql <<-SQL, **{ head_sha:, repository_id:, check_suite_id: }
          SELECT MAX(check_runs.id) AS check_run_id
            FROM check_runs
              JOIN check_suites
              ON check_runs.check_suite_id = check_suites.id
            WHERE check_suites.head_sha = :head_sha
              AND check_suites.repository_id = :repository_id
              AND check_suites.id = :check_suite_id
        SQL

        if latest_check_suite_run_only
          sql += Arel.sql <<-SQL
            AND check_runs.created_at >= IFNULL(check_suites.started_at, check_suites.created_at)
          SQL
        end

        sql += Arel.sql <<-SQL
          GROUP BY check_runs.name, check_runs.check_suite_id
          /* cross-shard-query-exempted */
        SQL

        CheckRun.connection.select_values(sql)
      end

      # rubocop:disable Metrics/MethodLength
      sig { params(created_at: ActiveSupport::TimeWithZone).returns(String).checked(:always).on_failure(:raise) }
      def created_at_bucket(created_at)
        if created_at > 1.day.ago
          "lt_1_day"
        elsif created_at > 7.days.ago
          "lt_7_days"
        elsif created_at > 30.days.ago
          "lt_30_days"
        elsif created_at > 60.days.ago
          "lt_60_days"
        elsif created_at > 90.days.ago
          "lt_90_days"
        else
          "gt_90_days"
        end
      end
    end
  end
end
