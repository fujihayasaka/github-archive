# typed: true
# frozen_string_literal: true

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("packages.package_transferred") do |payload|
    request_context = GitHub.context.to_hash
    message = {
      request_context: serializer.request_context(request_context),
      actor: serializer.user(payload[:actor]),
      package: serializer.package(payload[:package], total_size: payload[:size]),
      transferred_at: payload[:transferred_at],
      storage_service: serializer.package_file_storage_service(payload[:storage_service]),
      user_agent: payload[:user_agent],
      repository: serializer.repository(payload[:repository]),
      previous_repository: serializer.repository(payload[:previous_repository]),
      previous_owner_user: serializer.user(payload[:previous_owner_user]),
      previous_owner_org: serializer.organization(payload[:previous_owner_org]),
      previous_owner_id: payload[:previous_owner_id],
      previous_owner_global_id: payload[:previous_owner_global_id],
      event_id: request_context[:request_id] || SecureRandom.uuid,
    }

    publish(message, schema: "package_registry.v0.PackageTransferred", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe(/package\.(published|downloaded)/) do |payload|
    message = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      actor: serializer.user(payload[:actor]),
      repository: serializer.repository(payload[:repository]),
      action: payload[:action].to_s.upcase.to_sym,
      registry_package_id: payload[:registry_package_id],
      package_version: payload[:version],
      package_size: payload[:package_size],
      user_agent: payload[:user_agent],
    }

    publish(message, schema: "github.package_registry.v0.PackageEvent", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("package_registry.package_deleted") do |payload|
    request_context = GitHub.context.to_hash
    message = {
      request_context: serializer.request_context(request_context),
      actor: serializer.user(payload[:actor]),
      package: serializer.package(payload[:package], total_size: payload[:storage_bytes], version_count: payload[:version_count]),
      deleted_at: payload[:deleted_at],
      storage_service: serializer.package_file_storage_service(payload[:storage_service]),
      user_agent: payload[:user_agent],
      via_actions: payload[:via_actions],
      event_id: request_context[:request_id] || SecureRandom.uuid,
    }

    publish(message, schema: "package_registry.v0.PackageDeleted", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("package_registry.package_published") do |payload|
    request_context = GitHub.context.to_hash
    message = {
      request_context: serializer.request_context(request_context),
      actor: serializer.user(payload[:actor]),
      package: serializer.package(payload[:package], total_size: payload[:total_size], version_count: payload[:version_count]),
      published_at: payload[:published_at],
      storage_service: serializer.package_file_storage_service(payload[:storage_service]),
      user_agent: payload[:user_agent],
      via_actions: payload[:via_actions],
      event_id: request_context[:request_id] || SecureRandom.uuid,
      republished: payload[:republished],
      package_deleted_name: payload[:package_deleted_name]
    }

    publish(message, schema: "package_registry.v0.PackagePublished", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("package_registry.package_version_deleted") do |payload|
    request_context = GitHub.context.to_hash
    message = {
      request_context: serializer.request_context(request_context),
      actor: serializer.user(payload[:actor]),
      package: serializer.package(payload[:package]),
      version: serializer.package_version(payload[:version], files_count: payload[:files_count], size: payload[:size]),
      deleted_at: payload[:deleted_at],
      storage_service: serializer.package_file_storage_service(payload[:storage_service]),
      user_agent: payload[:user_agent],
      via_actions: payload[:via_actions],
      event_id: request_context[:request_id] || SecureRandom.uuid,
      bulk_delete: payload[:bulk_delete]
    }

    publish(message, schema: "package_registry.v0.PackageVersionDeleted", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("package_registry.package_version_downloaded") do |payload|
    publish(payload, schema: "package_registry.v0.PackageVersionDownloaded", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("package_registry.package_file_destroyed") do |payload|
    request_context = GitHub.context.to_hash
    message = {
        artifact_id: payload[:artifact_id],
        storage_service: serializer.package_file_storage_service(payload[:storage_service]),
        event_id: request_context[:request_id] || SecureRandom.uuid,
        repository: { id: payload[:repository_id] },
    }

    publish(message, schema: "package_registry.v0.PackageFileDestroyed", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("package_registry.package_version_published") do |payload|
    request_context = GitHub.context.to_hash
    message = {
      request_context: serializer.request_context(request_context),
      actor: serializer.user(payload[:actor]),
      package: serializer.package(payload[:package]),
      version: serializer.package_version(payload[:version], files_count: payload[:files_count], size: payload[:size]),
      published_at: payload[:published_at],
      storage_service: serializer.package_file_storage_service(payload[:storage_service]),
      user_agent: payload[:user_agent],
      repository: serializer.repository(payload[:repository]),
      via_actions: payload[:via_actions],
      event_id: request_context[:request_id] || SecureRandom.uuid,
      republished: payload[:republished],
      bulk_publish: payload[:bulk_publish],
      version_deleted_name: payload.has_key?(:version_deleted_name) ? payload[:version_deleted_name] : nil
    }

    publish(message, schema: "package_registry.v0.PackageVersionPublished", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("package_registry.package_file_published") do |payload|
    request_context = GitHub.context.to_hash
    message = {
        request_context: serializer.request_context(request_context),
        actor: serializer.user(payload[:actor]),
        package: serializer.package(payload[:package]),
        version: serializer.package_version(payload[:version], files_count: payload[:files_count], size: payload[:size]),
        published_at: payload[:published_at],
        storage_service: serializer.package_file_storage_service(payload[:storage_service]),
        user_agent: payload[:user_agent],
        repository: serializer.repository(payload[:repository]),
        via_actions: payload[:via_actions],
        file: serializer.package_file(payload[:file]),
        event_id: request_context[:request_id] || SecureRandom.uuid,
    }

    publish(message, schema: "package_registry.v0.PackageFilePublished", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("package_registry.package_version_migration_initiated") do |payload|
    publish(payload, schema: "registry_metadata.v0.VersionMigrationInitiated", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("package_registry.package_migration_complete") do |payload|
    publish(payload, schema: "registry_metadata.v0.IndexPackage", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("package_registry.namespace_cache_invalidate") do |payload|
    publish(payload, schema: "registry_metadata.v0.PackagesNamespaceCacheInvalidate", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V2 })
  end
end
