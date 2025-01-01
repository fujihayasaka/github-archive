# typed: true
# rubocop:disable GitHub/DoNotBranchOnRailsEnv
# frozen_string_literal: true

module GitHub
  module Config
    module Migration
      # 36 hours, or 60 seconds * 60 minutes * 24.
      MAX_GH_MIGRATOR_TIME = 60 * 60 * 36

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
