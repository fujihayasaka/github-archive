# typed: true
# frozen_string_literal: true

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("branch_protection_rule.create") do |payload|
    message = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      actor: serializer.user(payload[:actor]),
      repository: serializer.repository(payload[:repository]),
      repository_owner: serializer.user(payload[:repository_owner]),
      branch_protection_rule: serializer.branch_protection_rule(payload[:branch_protection_rule]),
      action: :CREATE,
    }

    publish(message, schema: "github.v1.BranchProtectionRuleChange", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("branch_protection_rule.update") do |payload|
    message = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      actor: serializer.user(payload[:actor]),
      repository: serializer.repository(payload[:repository]),
      repository_owner: serializer.user(payload[:repository_owner]),
      branch_protection_rule: serializer.branch_protection_rule(payload[:branch_protection_rule]),
      action: :UPDATE,
    }

    publish(message, schema: "github.v1.BranchProtectionRuleChange", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("branch_protection_rule.destroy") do |payload|
    message = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      actor: serializer.user(payload[:actor]),
      repository: serializer.repository(payload[:repository]),
      repository_owner: serializer.user(payload[:repository_owner]),
      branch_protection_rule: serializer.branch_protection_rule(payload[:branch_protection_rule]),
      action: :DESTROY,
    }

    publish(message, schema: "github.v1.BranchProtectionRuleChange", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end
end
