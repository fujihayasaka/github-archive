# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    module MapWarning
      def gh_migrator_map_warning?
        true
      end
    end

    class Error < StandardError
    end

    class MigrationError < StandardError
    end

    class AssociationFailed < MigrationError
      def gh_migrator_cli_message(cli:)
        "#{message}\n\n#{cli.enterprise_support}"
      end
    end

    class CannotMapToMissingTarget < MigrationError
      include MapWarning
    end

    class CannotRenameToExistingModel < MigrationError
      include MapWarning
    end

    class DGitImportError < MigrationError
      def gh_migrator_cli_message(cli:)
        "Repository import failed. #{cli.enterprise_support}"
      end
    end

    class RepositoryImportError < MigrationError
      def gh_migrator_cli_message(cli:)
        "Repository import failed. #{cli.enterprise_support}"
      end
    end

    class EmptyMigration < MigrationError
      def gh_migrator_cli_message(cli:)
        "Cannot process empty migration"
      end
    end

    class FailedMapping < MigrationError
      include MapWarning
    end

    class FailedSkip < MigrationError
      include MapWarning
    end

    class GuidCollision < MigrationError
      def gh_migrator_cli_message(cli:)
        message  = "'#{cli.script_name} prepare' halted, reusing a GUID can corrupt a migration. "
        message += "Run '#{cli.script_name} list' to see a list of GUIDs that have already been used.\n\n"
      end
    end

    class InvalidUserOrPersonalAccessToken < MigrationError
      def gh_migrator_cli_message(cli:)
        "Invalid user or personal access token\n#{cli.help}"
      end
    end

    class SvnMappingError < MigrationError
      def gh_migrator_cli_message(cli:)
        "Repository import failed. #{cli.enterprise_support}"
      end
    end

    class TimeoutError < MigrationError; end

    class UnresolvedConflicts < MigrationError
      def gh_migrator_cli_message(cli:)
        message  = "Conflicts still exist. Run '#{cli.script_name} conflicts -g #{cli.guid}' and use conflict resolution documentation.\n\n"
        message += "Documentation can be found at #{cli.documentation_url}"
      end
    end

    class UnsupportedSchemaVersion < MigrationError
      def gh_migrator_cli_message(cli:)
        "#{cli.script_name} does not support this migration archive schema version."
      end
    end

    class UnsupportedArchive < MigrationError
      def gh_migrator_cli_message(cli:)
        "schema.json does not exist in the archive and the schema could not be determined."
      end
    end

    class UnsupportedStorage < MigrationError; end
    class RepositoryRequired < MigrationError; end
    class OrganizationRequired < MigrationError; end
    class GuidRequired < MigrationError; end
    class CannotUnlockOnFailedImport < MigrationError; end
    class CannotUnlockImportAgain < MigrationError; end
    class CannotUnlockImportInProgress < MigrationError; end
    class MultipartUploadError < MigrationError; end
    class UnrecognizableUrlError < MigrationError; end
    class UnsupportedUploadableAsset < MigrationError; end
    class ExportFailure < MigrationError; end
    class SecurityException < MigrationError; end
    class InvalidArchivePermissions < MigrationError; end
    class ResourceExhaustedError < MigrationError; end
    class CleanupArchiveError < MigrationError; end
  end
end
