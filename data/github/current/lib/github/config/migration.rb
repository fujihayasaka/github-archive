# typed: true
# rubocop:disable GitHub/DoNotBranchOnRailsEnv
# frozen_string_literal: true

module GitHub
  module Config
    module Migration
      # 48 hours, or 60 seconds * 60 minutes * 48.
      MAX_GH_MIGRATOR_TIME = 60 * 60 * 48

      # Public: A migration coordinator.
      def migrator
        @migrator ||= GitHub::MigrationCoordinator.new(migrator: gh_migrator_proxy)
      end
      attr_writer :migrator

      # Internal.
      def gh_migrator_proxy
        GitHub::MigratorProxy.new
      end

      def gh_migrator_batch_size=(value)
        @gh_migrator_batch_size = if value.is_a?(Integer) && value.positive?
          value
        elsif GitHub.enterprise?
          1000
        else
          50
        end
      end
      attr_reader :gh_migrator_batch_size

      # Public: The maximum allowed export archive size in gigabytes.
      # Configurable on GHES via (value in GB):
      #   ghe-config app.github.migrations-max-export-archive-size-gb 80 && ghe-config-apply
      # Defaults to unlimited on enterprise, 40GB otherwise.
      #
      # Zero is a valid configured value and denotes "no limit" (unlimited).
      def migrations_max_export_archive_size_gb=(value)
        return unless value.is_a?(Integer) && value >= 0

        @migrations_max_export_archive_size_gb = value
      end

      def migrations_max_export_archive_size_gb
        @migrations_max_export_archive_size_gb ||= if GitHub.enterprise?
          Float::INFINITY
        else
          40
        end

        # Zero denotes "no limit", so surface it as unlimited to callers.
        @migrations_max_export_archive_size_gb.zero? ? Float::INFINITY : @migrations_max_export_archive_size_gb
      end

      # Public: The maximum allowable time for gh-migrator exports to run.
      def max_gh_migrator_export_time
        @max_gh_migrator_export_time ||= MAX_GH_MIGRATOR_TIME
      end
      attr_writer :max_gh_migrator_export_time

      # Public: The maximum allowable time for gh-migrator imports to run.
      def max_gh_migrator_import_time
        @max_gh_migrator_import_time ||= MAX_GH_MIGRATOR_TIME
      end
      attr_writer :max_gh_migrator_import_time

      # Sets the local file system path to store import-export staging files.
      #
      # Returns a String path.
      def migration_file_staging_path
        @migration_file_staging_path ||= if Rails.env.test?
          Rails.root.join("test/fixtures/gh-migrator/import-export-tmp").to_s
        # Use tmp directory for proxima and review-lab to avoid read-only container filesystem
        elsif GitHub.multi_tenant_enterprise? || GitHub.review_lab?
          "/tmp"
        elsif GitHub.enterprise?
          "/data/user/tmp"
        elsif Rails.env.production?
          "/data/github/shared/import-export-tmp"
        else
          Rails.root.join("tmp/import-export-tmp").to_s
        end
      end
      attr_writer :migration_file_staging_path

      def migration_file_base_path
        "migration"
      end
    end
  end

  extend Config::Migration
end
