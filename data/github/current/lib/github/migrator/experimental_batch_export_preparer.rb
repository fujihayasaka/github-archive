# typed: true
# frozen_string_literal: true

# ExperimentalBatchExportPreparer is a service object that will prepare a
# Repository and its dependencies to be exported.
#
# This class inherits from ExportPreparer and for the most part defaults to
# that parent class's behavior.
#
# The purpose of this special class is to allow for batched importers for
# certain very large repsositories which can't currently follow our standard
# import/export path due to size.
#
# In order to use this class, certain conditions must be met:
#   - The octoshift_experimental_incremental_migrations feature flag must be enabled for the source repo
#   - The repository must have date ranges specified in CUSTOMER_BATCHES
#   - The repository must have a key set in KV store with the batch start date
# If any of these conditions are not met, the behavior will default to the standard ExportPreparer path.
#
# The main difference in behavior is that this class will only export issues and pull requests based on the date ranges specified in this file.
# This enables customers to run multiple, smaller exports (and therefore imports)
# in order to get around size limits.
#
# This does not scope or batch the other meta data which is exported; we
# continue to export all milestones, teams, discussions as specified in
# ExportPreparer, because much of this data is used in references across repos.
#
# While this approach is then a bit redundant, because our importer is
# idempotent, this should not result in any duplicate data written to the
# target repo.

module GitHub
  class Migrator
    class ExperimentalBatchExportPreparer < ExportPreparer

      MIGRATION_BATCH_SIZE_TINY = 100
      MIGRATION_BATCH_SIZE_200 = 200
      MIGRATION_BATCH_SIZE_300 = 300
      MIGRATION_BATCH_SIZE_400 = 400
      MIGRATION_BATCH_SIZE_500 = 500
      MIGRATION_BATCH_SIZE_600 = 600
      MIGRATION_BATCH_SIZE_700 = 700
      MIGRATION_BATCH_SIZE_800 = 800
      MIGRATION_BATCH_SIZE_900 = 900
      MIGRATION_BATCH_SIZE_SMOL = 1_000
      MIGRATION_BATCH_SIZE_2500 = 2_500
      MIGRATION_BATCH_SIZE_5000 = 5_000
      MIGRATION_BATCH_SIZE_LARGE = 50_000
      MIGRATION_BATCH_SIZE_DEFAULT = 25_000

      def use_default_exporter?
        return true unless repository.feature_enabled?(:octoshift_experimental_incremental_migrations)

        false
      end

      private

      def migration_batch_size
        return @migration_batch_size if defined?(@migration_batch_size)
        if repository.feature_enabled?(:octoshift_experimental_incremental_migrations_tiny_batches)
          @migration_batch_size = MIGRATION_BATCH_SIZE_TINY
        elsif repository.feature_enabled?(:octoshift_experimental_incremental_migrations_200_batch)
          @migration_batch_size = MIGRATION_BATCH_SIZE_200
        elsif repository.feature_enabled?(:octoshift_experimental_incremental_migrations_300_batch)
          @migration_batch_size = MIGRATION_BATCH_SIZE_300
        elsif repository.feature_enabled?(:octoshift_experimental_incremental_migrations_400_batch)
          @migration_batch_size = MIGRATION_BATCH_SIZE_400
        elsif repository.feature_enabled?(:octoshift_experimental_incremental_migrations_500_batch)
          @migration_batch_size = MIGRATION_BATCH_SIZE_500
        elsif repository.feature_enabled?(:octoshift_experimental_incremental_migrations_600_batch)
          @migration_batch_size = MIGRATION_BATCH_SIZE_600
        elsif repository.feature_enabled?(:octoshift_experimental_incremental_migrations_700_batch)
          @migration_batch_size = MIGRATION_BATCH_SIZE_700
        elsif repository.feature_enabled?(:octoshift_experimental_incremental_migrations_800_batch)
          @migration_batch_size = MIGRATION_BATCH_SIZE_800
        elsif repository.feature_enabled?(:octoshift_experimental_incremental_migrations_900_batch)
          @migration_batch_size = MIGRATION_BATCH_SIZE_900
        elsif repository.feature_enabled?(:octoshift_experimental_incremental_migrations_small_batches)
          @migration_batch_size = MIGRATION_BATCH_SIZE_SMOL
        elsif repository.feature_enabled?(:octoshift_experimental_incremental_migrations_2500_batch)
          @migration_batch_size = MIGRATION_BATCH_SIZE_2500
        elsif repository.feature_enabled?(:octoshift_experimental_incremental_migrations_5000_batch)
          @migration_batch_size = MIGRATION_BATCH_SIZE_5000
        elsif repository.feature_enabled?(:octoshift_experimental_incremental_migrations_large_batches)
          @migration_batch_size = MIGRATION_BATCH_SIZE_LARGE
        else
          @migration_batch_size = MIGRATION_BATCH_SIZE_DEFAULT
        end
      end

      def exclude_projects
        return true if super

        repository.feature_enabled?(:octoshift_experimental_incremental_migrations_exclude_projects)
      end

      def add_milestones(repository)
        return if repository.feature_enabled?(:octoshift_experimental_incremental_migrations_exclude_milestones)

        super
      end

      def number_scoped_query(scope)
        scope.where(number: (current_migration_cursor)...(current_migration_cursor + migration_batch_size))
      end

      def current_migration_cursor
        return @current_migration_cursor if defined?(@current_migration_cursor)
        @current_migration_cursor = fetch_and_set_cursor
      end

      def fetch_and_set_cursor
        migration_state = OctoshiftBatchHelper::MigrationState.fetch_from_migration_guid(guid)
        current_cursor = migration_state.current_cursor

        if GitHub.flipper[:octoshift_experimental_incremental_migrations_backwards_cursor].enabled?(repository)
          migration_state.set_next_cursor(current_cursor - migration_batch_size)
        else
          migration_state.set_next_cursor(current_cursor + migration_batch_size)
        end

        current_cursor
      end

      def pull_request_ids_for_repository(repository)
        return super if use_default_exporter?

        pull_request_ids = []
        last_batch_id = T.let(0, T.untyped)

        batch_scope = number_scoped_query(repository.issues).with_pull_requests.limit(100_000).order(:pull_request_id)
        batch_ids = batch_scope.where("pull_request_id > ?", last_batch_id).pluck(:pull_request_id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)

        while batch_ids.any?
          pull_request_ids.concat(batch_ids)
          last_batch_id = batch_ids.last

          batch_ids = batch_scope.where("pull_request_id > ?", last_batch_id).pluck(:pull_request_id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        end

        pull_request_ids
      end

      def issue_ids_for_repository(repository)
        return super if use_default_exporter?

        issue_ids = []
        last_batch_id = T.let(0, T.untyped)

        batch_scope = number_scoped_query(repository.issues).without_pull_requests.limit(100_000).order(:id)
        batch_ids = batch_scope.where("id > ?", last_batch_id).pluck(:id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)

        while batch_ids.any?
          issue_ids.concat(batch_ids)
          last_batch_id = batch_ids.last

          batch_ids = batch_scope.where("id > ?", last_batch_id).pluck(:id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        end

        issue_ids
      end

      def all_issue_ids_for_repository(repository)
        return super if use_default_exporter?

        issue_ids = []
        last_batch_id = T.let(0, T.untyped)

        batch_scope = number_scoped_query(repository.issues).limit(100_000).order(:id)
        batch_ids = batch_scope.where("id > ?", last_batch_id).pluck(:id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)

        while batch_ids.any?
          issue_ids.concat(batch_ids)
          last_batch_id = batch_ids.last

          batch_ids = batch_scope.where("id > ?", last_batch_id).pluck(:id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        end

        issue_ids
      end
    end
  end
end
