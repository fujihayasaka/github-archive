# frozen_string_literal: true

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("notifications.delivery") do |payload|
    message = {
      user: serializer.user(payload[:user]),
      list_type: payload[:list_type],
      list_id: payload[:list_id].to_s,
      thread_type: payload[:thread_type],
      thread_id: payload[:thread_id].to_s,
      comment_type: payload[:comment_type],
      comment_id: payload[:comment_id].to_s,
      handler: payload[:handler].to_s.upcase,
      reason: payload[:reason],
      notification_id: payload[:notification_id],
    }

    publish(message, schema: "github.notifications.v0.NotificationDelivery", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("notifications.read") do |payload|
    message = {
      user: serializer.user(payload[:user]),
      list_type: payload[:list_type],
      list_id: payload[:list_id].to_s,
      thread_type: payload[:thread_type],
      thread_id: payload[:thread_id].to_s,
      comment_type: payload[:comment_type],
      comment_id: payload[:comment_id].to_s,
      handler: payload[:handler].to_s.upcase,
      action: "READ",
      version: payload.has_key?(:version) ? payload[:version].to_s.upcase : nil, # If key doesn't exist use default value
    }

    publish(message, schema: "github.notifications.v0.NotificationUserAction", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("notifications.unread") do |payload|
    message = {
      user: serializer.user(payload[:user]),
      list_type: payload[:list_type],
      list_id: payload[:list_id].to_s,
      thread_type: payload[:thread_type],
      thread_id: payload[:thread_id].to_s,
      comment_type: payload[:comment_type],
      comment_id: payload[:comment_id].to_s,
      handler: payload[:handler].to_s.upcase,
      action: "UNREAD",
      version: payload.has_key?(:version) ? payload[:version].to_s.upcase : nil, # If key doesn't exist use default value
    }

    publish(message, schema: "github.notifications.v0.NotificationUserAction", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("notifications.archive") do |payload|
    message = {
      user: serializer.user(payload[:user]),
      list_type: payload[:list_type],
      list_id: payload[:list_id].to_s,
      thread_type: payload[:thread_type],
      thread_id: payload[:thread_id].to_s,
      comment_type: payload[:comment_type],
      comment_id: payload[:comment_id].to_s,
      handler: payload[:handler].to_s.upcase,
      action: "ARCHIVE",
      version: payload.has_key?(:version) ? payload[:version].to_s.upcase : nil, # If key doesn't exist use default value
    }

    publish(message, schema: "github.notifications.v0.NotificationUserAction", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("notifications.unarchive") do |payload|
    message = {
      user: serializer.user(payload[:user]),
      list_type: payload[:list_type],
      list_id: payload[:list_id].to_s,
      thread_type: payload[:thread_type],
      thread_id: payload[:thread_id].to_s,
      comment_type: payload[:comment_type],
      comment_id: payload[:comment_id].to_s,
      handler: payload[:handler].to_s.upcase,
      action: "UNARCHIVE",
      version: payload.has_key?(:version) ? payload[:version].to_s.upcase : nil, # If key doesn't exist use default value
    }

    publish(message, schema: "github.notifications.v0.NotificationUserAction", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("notifications.unsubscribe") do |payload|
    message = {
      user: serializer.user(payload[:user]),
      list_type: payload[:list_type],
      list_id: payload[:list_id].to_s,
      thread_type: payload[:thread_type],
      thread_id: payload[:thread_id].to_s,
      comment_type: payload[:comment_type],
      comment_id: payload[:comment_id].to_s,
      handler: payload[:handler].to_s.upcase,
      action: "UNSUBSCRIBE",
      version: payload.has_key?(:version) ? payload[:version].to_s.upcase : nil, # If key doesn't exist use default value
    }

    publish(message, schema: "github.notifications.v0.NotificationUserAction", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("notifications.star") do |payload|
    message = {
      user: serializer.user(payload[:user]),
      list_type: payload[:list_type],
      list_id: payload[:list_id].to_s,
      thread_type: payload[:thread_type],
      thread_id: payload[:thread_id].to_s,
      comment_type: payload[:comment_type],
      comment_id: payload[:comment_id].to_s,
      handler: payload[:handler].to_s.upcase,
      action: "STAR",
      version: payload.has_key?(:version) ? payload[:version].to_s.upcase : nil, # If key doesn't exist use default value
    }

    publish(message, schema: "github.notifications.v0.NotificationUserAction", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("notifications.unstar") do |payload|
    message = {
      user: serializer.user(payload[:user]),
      list_type: payload[:list_type],
      list_id: payload[:list_id].to_s,
      thread_type: payload[:thread_type],
      thread_id: payload[:thread_id].to_s,
      comment_type: payload[:comment_type],
      comment_id: payload[:comment_id].to_s,
      handler: payload[:handler].to_s.upcase,
      action: "UNSTAR",
      version: payload.has_key?(:version) ? payload[:version].to_s.upcase : nil, # If key doesn't exist use default value
    }

    publish(message, schema: "github.notifications.v0.NotificationUserAction", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("browser.notifications.read") do |payload|
    user = payload[:client][:user]

    message = {
      user: serializer.user(user),
      list_type: payload[:list_type],
      list_id: payload[:list_id].to_s,
      thread_type: payload[:thread_type],
      thread_id: payload[:thread_id].to_s,
      comment_type: payload[:comment_type],
      comment_id: payload[:comment_id].to_s,
      handler: "WEB",
      action: "READ",
      version: payload.has_key?(:version) ? payload[:version].to_s.upcase : nil, # If key doesn't exist use default value
    }

    publish(message, schema: "github.notifications.v0.NotificationUserAction", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end
end
