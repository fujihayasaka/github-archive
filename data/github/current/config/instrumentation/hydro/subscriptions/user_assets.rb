# typed: true
# frozen_string_literal: true

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("user_asset.create") do |payload|
    user_asset = payload[:user_asset]

    message = {
      actor: serializer.user(user_asset.uploader),
      user_asset: serializer.user_asset(user_asset),
    }

    publish(message, schema: "github.v1.UserAssetCreate", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("user_asset.uploaded") do |payload|
    user_asset = payload[:user_asset]
    user = user_asset.uploader

    message = {
      actor: serializer.user(user),
      user_asset: serializer.user_asset(user_asset),
      upload_ip: serializer.ip_address(payload[:upload_ip]),
    }
    image_scan_message = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      actor: serializer.user(user_asset.uploader),
      upload_ip: serializer.ip_address(payload[:upload_ip]),
      image_model: {
        id: user_asset.id,
        guid: user_asset.guid,
        created_at: user_asset.created_at,
        updated_at: user_asset.updated_at,
        uploader_id: user&.id,
        uploader_login: user&.display_login,
        type: :USER_ASSET,
        size: user_asset.size,
        content_type: user_asset.content_type,
        canonical_url: user_asset.storage_external_url,
      },
    }
    publish(message, schema: "github.v1.UserAssetScan", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
    publish(image_scan_message, schema: "github.trust_safety.v0.ImageScan")
  end

  subscribe("user_asset.scan_requested") do |payload|
    user_asset = payload[:user_asset]
    user = user_asset.uploader

    message = {
      actor: serializer.user(user),
      user_asset: serializer.user_asset(user_asset),
      upload_ip: serializer.ip_address(GitHub.context[:actor_ip]),
    }
    image_scan_message = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      actor: serializer.user(user_asset.uploader),
      upload_ip: serializer.ip_address(GitHub.context[:actor_ip]),
      image_model: {
        id: user_asset.id,
        guid: user_asset.guid,
        created_at: user_asset.created_at,
        updated_at: user_asset.updated_at,
        uploader_id: user&.id,
        uploader_login: user&.display_login,
        type: :USER_ASSET,
        size: user_asset.size,
        content_type: user_asset.content_type,
        canonical_url: user_asset.storage_external_url,
      },
    }
    publish(message, schema: "github.v1.UserAssetScan", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
    publish(image_scan_message, schema: "github.trust_safety.v0.ImageScan")
  end
end
