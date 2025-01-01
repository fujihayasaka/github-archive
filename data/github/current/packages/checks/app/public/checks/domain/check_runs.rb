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

      # Get the IDs of the CheckRuns for the check suite(s) provided and the repository provided.
      # Note the distinction between this and the following method being that this one does not require a head sha
      # and so is suitable for call sites that have check suite IDs but not objects.
      #
      # @param repository_id The Repository ID to scope to.
      # @param check_suite_ids The CheckSuite IDs to scope to.
      # @param limit The maximum number of CheckRuns to return.
      # @return The IDs for the CheckRuns
      sig do
        params(repository_id: Integer, check_suite_ids: T::Array[Integer], limit: Integer).
        returns(T::Array[Integer]).
        checked(:always).
        on_failure(:raise)
      end
      def ids_for_suite_ids(repository_id:, check_suite_ids:, limit:)
        scope = CheckRun.where(repository_id: repository_id, check_suite_id: check_suite_ids).
        limit(limit).
        pluck(:id)
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

        age_bucket = record_age(check_suite)
        GitHub.logger.info(
          "code.namespace" => self.class.name,
          "code.function" => __method__,
          "gh.repository.id" => check_suite.repository_id,
          "gh.repository.head_sha" => check_suite.head_sha,
          "gh.actions.check_suite.id" => check_suite.id,
          "gh.actions.check_suite.age_bucket" => age_bucket,
          "gh.actions.check_runs.size" => ids.size,
        )

        ids
      end

      # Get all the latest CheckRuns for the check suite.
      #
      # Note: this method is unsafe because it is unbounded. Please use `latest_for_check_suite` instead.
      #
      # @param check_suite The check suite to scope to.
      # @return The latest CheckRuns for the given check suite.
      # rubocop:disable Metrics/MethodLength
      sig do
        params(check_suite: ICheckSuite, status_not: T.nilable(Symbol)).
        returns(T::Array[CheckRun]).
        checked(:always).
        on_failure(:raise)
      end
      def unsafe_latest_for_check_suite(check_suite, status_not: nil)
        ActiveRecord::Base.connected_to(role: :reading) do
          relation = latest_relation(
            repository_id: check_suite.repository_id,
            check_suite_id: check_suite.id,
            head_sha: check_suite.head_sha,
            latest_check_suite_run_only: check_suite.actions_app?
          )

          if status_not
            relation = relation.where.not(status: status_not)
          end

          results = relation.to_a

          age_bucket = record_age(check_suite)
          GitHub.logger.info(
            "code.namespace" => self.class.name,
            "code.function" => __method__,
            "gh.repository.id" => check_suite.repository_id,
            "gh.repository.head_sha" => check_suite.head_sha,
            "gh.actions.check_suite.id" => check_suite.id,
            "gh.actions.check_suite.age_bucket" => age_bucket,
            "gh.actions.check_runs.size" => results.size,
          )

          results
        end
      end

      # Get the latest CheckRuns for the check suite.
      #
      # TODO: Predicates to support:
      # - conclusion
      # - for_app_id (join with check_suites)
      #
      # @param check_suite The check suite to scope to.
      # @return The latest CheckRuns for the given check suite.
      # rubocop:disable Metrics/MethodLength
      sig do
        params(check_suite: ICheckSuite, pagination: GH::Pagination::Base, status: T.nilable(Symbol), status_not: T.nilable(Symbol), name_or_display_name: T.nilable(String), sorts: T.nilable(T::Array[GH::Pagination::Sort])).
        returns(GH::Domain::Collection[CheckRun]).
        checked(:always).
        on_failure(:raise)
      end
      def latest_for_check_suite(check_suite, pagination:, status: nil, status_not: nil, name_or_display_name: nil, sorts: nil)
        raise ArgumentError, "cannot pass both status and status_not" if status && status_not

        ActiveRecord::Base.connected_to(role: :reading) do
          relation = latest_relation(
            repository_id: check_suite.repository_id,
            check_suite_id: check_suite.id,
            head_sha: check_suite.head_sha,
            latest_check_suite_run_only: check_suite.actions_app?
          )

          if status
            relation = relation.where(status:)
          end

          if status_not
            relation = relation.where.not(status: status_not)
          end

          if name_or_display_name
            relation = relation.where(name: name_or_display_name).or(relation.where(display_name: name_or_display_name))
          end

          results = GH::Pagination::Paginator.paginate(scope: relation, pagination:, sorts:)

          age_bucket = record_age(check_suite)
          GitHub.logger.info(
            "code.namespace" => self.class.name,
            "code.function" => __method__,
            "gh.repository.id" => check_suite.repository_id,
            "gh.repository.head_sha" => check_suite.head_sha,
            "gh.actions.check_suite.id" => check_suite.id,
            "gh.actions.check_suite.age_bucket" => age_bucket,
            "gh.actions.check_runs.size" => results.size,
          )

          results
        end
      end

      # Get the latest CheckRuns for the given SHAs in the repository.
      #
      # @param check_suite The check suite to scope to.
      # @param first_only Whether to get only the first CheckRun.
      # @return The latest CheckRuns for the given check suite.
      # rubocop:disable Metrics/MethodLength
      sig do
        params(head_shas: T::Array[String], repository_id: Integer).
        returns(T::Hash[String, T::Array[CheckRun]]).
        checked(:always).
        on_failure(:raise)
      end
      def latest_for_shas(head_shas, repository_id:)
        ActiveRecord::Base.connected_to(role: :reading) do
          # Callers assume that we have an entry in the returned hash for each head SHA, even if there are no results
          # for it, so always use that as our starting point.
          results_by_head_sha = {}
          head_shas.each do |sha|
            results_by_head_sha[sha] = []
          end

          check_suite_ids = CheckRun.connection.select_values(Arel.sql(<<-SQL, head_shas: head_shas, repository_id: repository_id))
            SELECT MAX(check_suites.id)
              FROM check_suites
              WHERE check_suites.head_sha IN (:head_shas)
                AND check_suites.repository_id = :repository_id
                AND check_suites.hidden = FALSE
                AND check_suites.workflow_file_path IS NOT NULL
              GROUP BY check_suites.github_app_id, check_suites.workflow_file_path, check_suites.event, check_suites.head_sha

            UNION

            SELECT check_suites.id
              FROM check_suites
              WHERE check_suites.head_sha IN (:head_shas)
                AND check_suites.repository_id = :repository_id
                AND check_suites.workflow_file_path IS NULL
          SQL
          return results_by_head_sha if check_suite_ids.empty?

          id_head_sha_pairs = CheckRun.connection.select_rows(Arel.sql(<<-SQL, ids: check_suite_ids, repository_id: repository_id))
            SELECT MAX(check_runs.id) AS check_run_id, check_suites.head_sha AS head_sha
            FROM check_runs
              JOIN check_suites
              ON check_runs.check_suite_id = check_suites.id
            WHERE check_runs.check_suite_id IN (:ids)
              AND check_suites.repository_id = :repository_id
              AND (check_suites.workflow_file_path IS NULL
                OR check_runs.created_at >= IFNULL(check_suites.started_at, check_suites.created_at))
              AND check_runs.repository_id = :repository_id
            GROUP BY check_runs.name, check_runs.check_suite_id, check_suites.head_sha
          SQL
          return results_by_head_sha if id_head_sha_pairs.empty?

          id_to_head_sha = {}
          check_run_ids = []
          id_head_sha_pairs.each do |id, head_sha|
            id_to_head_sha[id] = head_sha
            check_run_ids << id
          end

          check_runs = CheckRun.where(id: check_run_ids, repository_id: repository_id).order(id: :desc).to_a
          check_runs_by_head_sha = {}
          check_runs.each do |check_run|
            head_sha = id_to_head_sha[check_run.id]
            next if head_sha.nil?

            existing_runs = check_runs_by_head_sha[head_sha]
            if existing_runs.nil?
              existing_runs = []
              check_runs_by_head_sha[head_sha] = existing_runs
            end

            existing_runs << check_run
          end

          head_shas.each do |sha|
            results_by_head_sha[sha] = check_runs_by_head_sha[sha] || []
          end

          GitHub.logger.info(
            "code.namespace" => self.class.name,
            "code.function" => __method__,
            "gh.repository.id" => repository_id,
            "gh.repository.head_shas" => head_shas,
            "gh.actions.check_runs.size" => results_by_head_sha.size,
          )

          results_by_head_sha
        end
      end

      # Get the CheckRun for the given ID in the repository.
      #
      # @param id The ID of the CheckRun to get.
      # @param repository_id The Repository ID to scope to.
      # @return The CheckRun for the given ID in the repository.
      sig do
        params(id: Integer, repository_id: Integer).
        returns(T.nilable(CheckRun)).
        checked(:always).
        on_failure(:raise)
      end
      def for_id(id, repository_id:)
        ActiveRecord::Base.connected_to(role: :reading) do
          CheckRun.find_by(id:, repository_id:)
        end
      end

      # Get the first CheckRun for the given check suite.
      #
      # @param check_suite The check suite to scope to.
      # @return The first CheckRun for the given check suite.
      sig do
        params(check_suite: ICheckSuite).
        returns(T.nilable(CheckRun)).
        checked(:always).
        on_failure(:raise)
      end
      def first_for_check_suite(check_suite)
        latest_for_check_suite(check_suite,
          pagination: GH::Pagination::Offset.new(per_page: 1, page: 1),
          sorts: [GH::Pagination::Sort.new(field: "id", direction: GH::Pagination::Sort::Direction::ASC)]
        ).first
      end

      # Get the CheckRun for the given ID.
      #
      # Note: this method is unsafe because it is not scoped to a repository, which means it requires a scatter query
      # all our shards. Please use `for_id` instead.
      #
      # @param id The ID of the CheckRun to get.
      # @param repository_id The Repository ID to scope to.
      # @return The CheckRun for the given ID in the repository.
      sig do
        params(id: Integer).
        returns(T.nilable(CheckRun)).
        checked(:always).
        on_failure(:raise)
      end
      def unsafe_for_id(id)
        ActiveRecord::Base.connected_to(role: :reading) do
          CheckRun.find_by(id:)
        end
      end

      # Get the CheckRuns for the given ID in the repository.
      #
      # @param ids The IDs of the CheckRun to get.
      # @param repository_id The Repository ID to scope to.
      # @return The paginated CheckRuns for the given IDs in the repository.
      sig do
        params(ids: T::Array[Integer], repository_id: Integer, pagination: GH::Pagination::Base).
        returns(GH::Domain::Collection[CheckRun]).
        checked(:always).
        on_failure(:raise)
      end
      def for_ids(ids, repository_id:, pagination:)
        ActiveRecord::Base.connected_to(role: :reading) do
          scope = CheckRun.where(id: ids, repository_id:)
          GH::Pagination::Paginator.paginate(scope:, pagination:)
        end
      end

      # Get the CheckRuns for the given ID in the repository.
      #
      # Note: this is unsafe because it is unbounded. Use `for_ids` instead.
      #
      # @param ids The IDs of the CheckRun to get.
      # @param repository_id The Repository ID to scope to.
      # @return The CheckRuns for the given IDs in the repository.
      sig do
        params(ids: T::Array[Integer], repository_id: Integer).
        returns(T::Array[CheckRun]).
        checked(:always).
        on_failure(:raise)
      end
      def unsafe_for_ids(ids, repository_id:)
        ActiveRecord::Base.connected_to(role: :reading) do
          CheckRun.where(id: ids, repository_id:).to_a
        end
      end

      # Get whether there are any CheckRuns for the given CheckSuite.
      #
      # @param check_suite The CheckSuite to check.
      # @return Whether there are any CheckRuns for the given CheckSuite.
      sig do
        params(check_suite: ICheckSuite).
        returns(T::Boolean).
        checked(:always).
        on_failure(:raise)
      end
      def any_for_check_suite?(check_suite)
        age_bucket = record_age(check_suite)
        GitHub.logger.info(
          "code.namespace" => self.class.name,
          "code.function" => __method__,
          "gh.repository.id" => check_suite.repository_id,
          "gh.repository.head_sha" => check_suite.head_sha,
          "gh.actions.check_suite.id" => check_suite.id,
          "gh.actions.check_suite.age_bucket" => age_bucket,
        )

        for_check_suite(check_suite:, pagination: GH::Pagination::Offset.new(per_page: 1, page: 1)).any?
      end

      # Prefetch the data for the given properties on the CheckRuns.
      #
      # @param check_runs The CheckRuns to prefetch.
      # @param properties The properties to prefetch.
      # @return The CheckRuns with their data prefetched.
      sig do
        type_parameters(:CollectionType).
        params(check_runs: T.all(T::Enumerable[CheckRun], T.type_parameter(:CollectionType)), properties: T::Array[Symbol]).
        returns(T.all(T::Enumerable[CheckRun], T.type_parameter(:CollectionType))).
        checked(:always).
        on_failure(:raise)
      end
      def prefetch(check_runs, properties)
        GitHub::PrefillAssociations.prefill_associations(check_runs, properties)
        check_runs
      end

      # Get the CheckRuns for the given CheckSuite.
      #
      # @param check_suite The CheckSuite to get.
      # @param pagination The pagination to use.
      # @param sorts The sorts to use.
      # @param external_id The external ID to filter by, if provided.
      # @param name The Check Run name to scope to, if provided.
      # @return The CheckRuns for the given CheckSuite.
      sig do
        params(check_suite: ICheckSuite, pagination: GH::Pagination::Base, sorts: T.nilable(T::Array[GH::Pagination::Sort]), name: (T.nilable(String)), external_id: T.nilable(String)).
        returns(GH::Domain::Collection[CheckRun]).
        checked(:always).
        on_failure(:raise)
      end
      def for_check_suite(check_suite:, pagination:, sorts: nil, name: nil, external_id: nil)
        ActiveRecord::Base.connected_to(role: :reading) do
          scope = CheckRun.where(check_suite_id: check_suite.id, repository_id: check_suite.repository_id)
          scope = scope.where(name:) if name
          scope = scope.where(external_id:) if external_id

          age_bucket = record_age(check_suite)
          GitHub.logger.info(
            "code.namespace" => self.class.name,
            "code.function" => __method__,
            "gh.repository.id" => check_suite.repository_id,
            "gh.actions.check_suite.id" => check_suite.id,
            "gh.actions.check_suite.age_bucket" => age_bucket,
          )

          GH::Pagination::Paginator.paginate(scope:, pagination:, sorts:)
        end
      end

      # Get the summaries for the SHAs.
      #
      # @param shas The SHAs to get summaries for.
      # @param repository_id The Repository ID to scope to.
      # @return The summaries for the given SHAs.
      sig do
        params(shas: T::Array[String], repository_id: Integer).
        returns(T::Array[T::Hash[String, T.untyped]]).
        checked(:always).
        on_failure(:raise)
      end
      def summaries_for_shas(shas, repository_id:)
        ActiveRecord::Base.connected_to(role: :reading) do
          sql = Arel.sql <<-SQL, **{ head_shas: shas, repository_id: }
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
          check_suite_ids = CheckSuite.connection.select_values(sql)

          if check_suite_ids.length > 0
            sql = Arel.sql <<-SQL, **{ check_suite_ids:, repository_id: }
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
            hash_results = CheckRun.connection.select_all(sql).to_a
          else
            hash_results = []
          end

          hash_results.each do |row|
            row["conclusion"] = CheckRun::conclusions.key(row["conclusion"])
          end

          hash_results
        end
      end

      # Get the last CheckRun for the given CheckSuite.
      # Last here meaning highest ID, not necessarily latest created.
      #
      # @param check_suite The CheckSuite to get runs for.
      # @param repository_id The Repository ID to scope to.
      # @param name The Check Run name to scope to, if provided.
      # @param external_id The external ID to filter by, if provided.
      # @return The last CheckRun for the given CheckSuite.
      sig do
        params(check_suite: ICheckSuite, repository_id: Integer, name: T.nilable(String), external_id: T.nilable(String)).
        returns(T.nilable(CheckRun)).
        checked(:always).
        on_failure(:raise)
      end
      def last_for_check_suite(check_suite:, repository_id:, name: nil, external_id: nil)
        for_check_suite(
          check_suite:,
          pagination: GH::Pagination::Offset.new(per_page: 1, page: 1),
          sorts: [
            GH::Pagination::Sort.new(
              field: "id",
              direction: GH::Pagination::Sort::Direction::DESC)
          ],
          name:,
          external_id:
        ).first
      end

      # Delete the CheckRuns for the given IDs in the repository.
      #
      # @param ids The IDs of the CheckRuns to delete.
      # @param repository_id The Repository ID to scope to.
      # @param batch_size The number of CheckRuns to delete at a time (optional). Defaults to 50 to avoid excessive
      # locking of database rows, do not increase without good reason.
      # @return The number of CheckRuns deleted.
      sig do
        params(repository_id: Integer, ids: T::Array[Integer], batch_size: Integer).
        returns(Integer).
        checked(:always).
        on_failure(:raise)
      end
      def delete_for_ids(repository_id:, ids:, batch_size: 50)
        ActiveRecord::Base.connected_to(role: :writing) do
          ids = ids.uniq
          return 0 if ids.empty?

          deleted = 0
          ids.each_slice(batch_size) do |batch|
            CheckRun.throttle do
              deleted += CheckRun.where(id: batch, repository_id:).delete_all
            end
          end
          deleted
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

      sig { params(check_suite: ICheckSuite).void.checked(:always).on_failure(:raise) }
      def record_age(check_suite)
        created_at_bucket = created_at_bucket(check_suite.created_at)
        GitHub.dogstats.increment("actions.checks.domain.check_runs.age", tags: ["bucket:#{created_at_bucket}"])
        created_at_bucket
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
