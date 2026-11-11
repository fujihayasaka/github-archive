# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module RegistryMetadata
      autoload :ArtifactStorageEventProcessor, "github/stream_processors/registry_metadata/artifact_storage_event_processor"
      autoload :VersionPublishedProcessor, "github/stream_processors/registry_metadata/version_published_processor"
      autoload :VersionDeletedProcessor, "github/stream_processors/registry_metadata/version_deleted_processor"
      autoload :VersionDownloadedProcessor, "github/stream_processors/registry_metadata/version_downloaded_processor"
      autoload :PackagePublishedAuditProcessor, "github/stream_processors/registry_metadata/package_published_audit_processor"
      autoload :PackageDeletedAuditProcessor, "github/stream_processors/registry_metadata/package_deleted_audit_processor"
      autoload :RmsVersionPublishedAuditProcessor, "github/stream_processors/registry_metadata/rms_version_published_audit_processor"
      autoload :RmsVersionDeletedAuditProcessor, "github/stream_processors/registry_metadata/rms_version_deleted_audit_processor"
      autoload :LayerPublishedProcessor, "github/stream_processors/registry_metadata/layer_published_processor"
      autoload :LayerDownloadedProcessor, "github/stream_processors/registry_metadata/layer_downloaded_processor"
      autoload :LayerDeletedProcessor, "github/stream_processors/registry_metadata/layer_deleted_processor"
      autoload :VersionMigrationStatusProcessor, "github/stream_processors/registry_metadata/version_migration_status_processor"
      autoload :MigrationDataSyncEventProcessor, "github/stream_processors/registry_metadata/migration_data_sync_event_processor"
      autoload :RepositoryAccessRemovalProcessor, "github/stream_processors/registry_metadata/repository_access_removal_processor"
      autoload :CommonMethods, "github/stream_processors/registry_metadata/common_methods"
    end
  end
end
