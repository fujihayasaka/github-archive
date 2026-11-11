# typed: true
# frozen_string_literal: true

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("blob.excerpt") do |payload|
    message = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      actor: serializer.user(payload[:actor]),
      repository: serializer.repository(payload[:repository]),
      path: payload[:path],
      blob_oid: payload[:blob_oid],
      first_line: payload[:first_line],
      last_line: payload[:last_line],
      direction: payload[:direction],
    }

    publish(message, schema: "github.v1.BlobExcerptLoaded", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("blob.edit.page_view") do |payload|
    path = payload[:path]&.dup&.force_encoding(Encoding::UTF_8)
    message = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      actor: serializer.user(payload[:actor]),
      repository: serializer.repository(payload[:repository]),
      target_repository: serializer.repository(payload[:target_repository]),
      branch: payload[:branch]&.dup&.force_encoding(Encoding::UTF_8),
      can_commit_to_branch: payload[:can_commit_to_branch],
      path: path,
      file_extension: serializer.file_extension(path),
    }

    publish(message, schema: "github.v1.BlobEditPageView", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("blob.new.page_view") do |payload|
    message = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      actor: serializer.user(payload[:actor]),
      repository: serializer.repository(payload[:repository]),
      target_repository: serializer.repository(payload[:target_repository]),
      branch: payload[:branch]&.dup&.force_encoding(Encoding::UTF_8),
      can_commit_to_branch: payload[:can_commit_to_branch],
    }

    publish(message, schema: "github.v1.BlobNewPageView", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe(/blob\.(new|edit|delete)\.succeeded/) do |payload|
    path = payload[:path]&.dup&.force_encoding(Encoding::UTF_8)
    message = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      actor: serializer.user(payload[:actor]),
      repository: serializer.repository(payload[:repository]),
      target_repository: serializer.repository(payload[:target_repository]),
      branch: payload[:branch]&.dup&.force_encoding(Encoding::UTF_8),
      can_commit_to_branch: payload[:can_commit_to_branch],
      target_branch: payload[:target_branch]&.dup&.force_encoding(Encoding::UTF_8),
      path: path,
      file_extension: serializer.file_extension(path),
      action: serializer.enum_from_string(payload[:action]),
    }

    publish(message, schema: "github.v1.BlobActionSucceeded", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe(/(browser\.)?code_navigation\.(view_blob_symbols_available|view_blob_symbols_unavailable|view_blob_language_not_supported|click_on_symbol|navigate_to_definition|click_on_blob_definitions|navigate_to_blob_definition|click_on_references|navigate_to_reference|click_on_definitions|retry_definition|retry_references|retry_after_timeout)/) do |payload|
    repository = Repositories.domain.by_id(payload[:repository_id].to_i)
    message = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      repository: serializer.repository(repository),
      action: payload[:action].to_s.upcase.to_sym,
      ref: payload[:ref]&.dup&.force_encoding(Encoding::UTF_8),
      language: payload[:language],
      backend: payload[:backend],
      code_nav_context: payload[:code_nav_context],
      retry_backend: payload[:retry_backend],
      cross_repo_results_included: payload[:cross_repo_results_included],
      in_repo_result_count: payload[:in_repo_result_count],
      cross_repo_result_count: payload[:cross_repo_result_count],
    }
    message[:actor] = serializer.user(User.find_by(id: payload[:user_id])) if payload[:user_id]

    publish(message, schema: "github.code_navigation.v0.JumpToEvent", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end
end
