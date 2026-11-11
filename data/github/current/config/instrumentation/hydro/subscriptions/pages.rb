# typed: true
# frozen_string_literal: true

# Hydro event subscriptions related to pages.
Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("pages.build") do |payload|
    message = {
      request_context: serializer.request_context(GitHub.context.to_hash,
        overrides: browser_request_context_overrides(payload)),
      actor: serializer.user(payload[:actor]),
      page: serializer.page(payload[:page]),
      repository_owner: serializer.user(payload[:repository_owner]),
    }
    publish(message, schema: "github.v1.RepositoryPagesBuild", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("pages.cname_change") do |payload|
    message = {
      request_context: serializer.request_context(GitHub.context.to_hash,
        overrides: browser_request_context_overrides(payload)),
      actor: serializer.user(payload[:actor]),
      page: serializer.page(payload[:page]),
      cname: payload[:cname]&.to_s,
      old_cname: payload[:old_cname]&.to_s,
    }
    publish(message, schema: "github.v1.RepositoryPagesCnameChange", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("pages.visibility_change") do |payload|
    message = {
      request_context: serializer.request_context(GitHub.context.to_hash,
        overrides: browser_request_context_overrides(payload)),
      actor: serializer.user(payload[:actor]),
      page: serializer.page(payload[:page]),
      public: payload[:public]
    }
    publish(message, schema: "github.v1.RepositoryPagesVisibilityChange", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("pages.actions.build") do |payload|
    message = {
      actor: serializer.user(payload[:actor]),
      page: serializer.page(payload[:page]),
      repository_owner: serializer.user(payload[:repository_owner]),
      aqueduct_message: payload[:aqueduct_message],
      artifact_hash: payload[:artifact_hash]
    }
    publish(message, schema: "github.v1.RepositoryPagesActionBuild")
  end
end
