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

  subscribe("browser.notifications.unwatch_suggestion_event.unwatched_all") do |payload|
    user = payload[:client][:user]

    next unless user.present?

    message = {
      event: :UNWATCHED_ALL,
      user: serializer.user(user),
      snapshot_date: payload[:snapshot_date],
      algorithm_version: payload[:algorithm_version].to_s
    }

    publish(message, schema: "github.notifications.v0.UnwatchSuggestionEvent", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("browser.notifications.unwatch_suggestion_event.shown_list") do |payload|
    user = serializer.user(payload[:client][:user])
    message = {
      event: :SHOWN_LIST,
      user: user,
      snapshot_date: payload[:snapshot_date],
      algorithm_version: payload[:algorithm_version]
    }

    publish(message, schema: "github.notifications.v0.UnwatchSuggestionEvent", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("browser.notifications.unwatch_suggestion_event.unwatch_repository") do |payload|
    repo = Repository.find_by(id: payload[:repository_id])
    next unless repo.present?

    user = serializer.user(payload[:client][:user])
    repository = serializer.repository(repo)

    message = {
      event: :UNWATCHED_REPO,
      user: user,
      snapshot_date: payload[:snapshot_date],
      algorithm_version: payload[:algorithm_version].to_s,
      repository: repository,
    }

    publish(message, schema: "github.notifications.v0.UnwatchSuggestionEvent", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("browser.notifications.unwatch_suggestion_event.shown_alert") do |payload|
    user = serializer.user(payload[:client][:user])
    message = {
      event: :SHOWN_ALERT,
      user: user,
      snapshot_date: payload[:snapshot_date],
      algorithm_version: payload[:algorithm_version].to_s
    }

    repo = Repository.find_by(id: payload[:repository_id])
    message[:repository] = serializer.repository(repo) if repo.present?

    publish(message, schema: "github.notifications.v0.UnwatchSuggestionEvent", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("browser.notifications.unwatch_suggestion_event.dismissed_alert") do |payload|
    user = serializer.user(payload[:client][:user])
    message = {
      event: :DISMISSED_ALERT,
      user: user,
      snapshot_date: payload[:snapshot_date],
      algorithm_version: payload[:algorithm_version].to_s
    }

    repo = Repository.find_by(id: payload[:repository_id])
    message[:repository] = serializer.repository(repo) if repo.present?

    publish(message, schema: "github.notifications.v0.UnwatchSuggestionEvent", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("browser.notifications.unwatch_suggestion_event.dismissed_list") do |payload|
    user = serializer.user(payload[:client][:user])
    message = {
      event: :DISMISSED_LIST,
      user: user,
      snapshot_date: payload[:snapshot_date],
      algorithm_version: payload[:algorithm_version].to_s
    }

    publish(message, schema: "github.notifications.v0.UnwatchSuggestionEvent", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end
end
