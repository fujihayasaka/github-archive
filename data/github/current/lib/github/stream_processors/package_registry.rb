# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module PackageRegistry
      autoload :PackageRestoreMigrationProcessor, "github/stream_processors/package_registry/package_restore_migration_processor"
      autoload :SyncV1PackageVersionDeleteToV2Processor, "github/stream_processors/package_registry/sync_v1_package_version_delete_to_v2_processor"
      autoload :PackageDeleteSyncProcessor, "github/stream_processors/package_registry/package_delete_sync_processor"
      autoload :PackageVersionRestoreMigrationProcessor, "github/stream_processors/package_registry/package_version_restore_migration_processor"
      autoload :DownloadActivityProcessor, "github/stream_processors/package_registry/download_activity_processor"
      autoload :PackageDeletedAuditProcessor, "github/stream_processors/package_registry/package_deleted_audit_processor"
      autoload :PackageFilePublishedProcessor, "github/stream_processors/package_registry/package_file_published_processor"
      autoload :PackagePublishedAuditProcessor, "github/stream_processors/package_registry/package_published_audit_processor"
      autoload :PackageTransferredProcessor, "github/stream_processors/package_registry/package_transferred_processor"
      autoload :PackageVersionDeletedAuditProcessor, "github/stream_processors/package_registry/package_version_deleted_audit_processor"
      autoload :PackageVersionDeletedProcessor, "github/stream_processors/package_registry/package_version_deleted_processor"
      autoload :PackageVersionPublishedAuditProcessor, "github/stream_processors/package_registry/package_version_published_audit_processor"
    end
  end
end
