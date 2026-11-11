# typed: true
# frozen_string_literal: true

# These are Hydro event subscriptions related to Issues.

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("issue.create") do |payload|
    # Only publish the following messages if this Issue is not a Pull Request.
    next if payload[:issue].pull_request?

    serialized_repository_domain, serialized_actor_domain, serialized_repository_owner_domain = T.let(nil, T.untyped)
    ActiveRecord::Base.connected_to(role: :reading) do
      serialized_repository_domain = serializer.repository_domain(payload[:repository])
      serialized_actor_domain = serializer.user_domain(payload[:actor])
      serialized_repository_owner_domain = serializer.user_domain(payload[:repository_owner])
    end

    issue_created_msg = {
      repository: serialized_repository_domain,
      actor: serialized_actor_domain,
      issue: serializer.issue_domain(payload[:issue]),
      repository_owner: serialized_repository_owner_domain,
    }

    publish(issue_created_msg, schema: "github.domain_events.v0.IssueCreated", publisher: GitHub.low_latency_hydro_publisher, topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat

    serialized_actor, serialized_repository, serialized_repository_owner, serialized_issue_creator, serialized_issue_template, serialized_issue_type = T.let(nil, T.untyped)
    ActiveRecord::Base.connected_to(role: :reading) do
      serialized_actor = serializer.user(payload[:actor])
      serialized_repository = serializer.repository(payload[:repository])
      serialized_repository_owner = serializer.user(payload[:repository_owner])
      serialized_issue_creator = serializer.user(payload[:issue_creator])
      serialized_issue_template = serializer.issue_template(payload[:template])
      serialized_issue_type = serializer.issue_type(payload[:issue_type])
    end

    serialized_spamurai_form_signals = serializer.spamurai_form_signals(GitHub.context[:spamurai_form_signals])
    serialized_specimen_body = serializer.specimen_data(payload[:issue].body)
    serialized_specimen_title = serializer.specimen_data(payload[:issue].title)
    serialized_request_context = serializer.request_context(GitHub.context.to_hash)
    serialized_issue = serializer.issue(payload[:issue])

    from_template_msg = {
      request_context: serialized_request_context,
      actor: serialized_actor,
      repository: serialized_repository,
      repository_owner: serialized_repository_owner,
      issue: serialized_issue,
      issue_creator: serialized_issue_creator,
      issue_template: serialized_issue_template,
      issue_type: serialized_issue_type,
      is_duplicated: payload[:is_duplicated].present? ? payload[:is_duplicated] : false,
    }

    publish(from_template_msg, schema: "github.v1.IssueCreateTemplate", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat

    user_generated_content_msg = {
      request_context: serialized_request_context,
      spamurai_form_signals: serialized_spamurai_form_signals,
      action_type: :CREATE,
      content_type: :ISSUE,
      actor: serialized_actor,
      original_type_url: GitHub::Config::HydroConfig.build_type_url("github.v1.IssueCreate"),
      content_database_id: serialized_issue[:id_value],
      content_global_relay_id: serialized_issue[:global_relay_id],
      content_created_at: serialized_issue[:created_at],
      content_updated_at: serialized_issue[:updated_at],
      title: serialized_specimen_title,
      content: serialized_specimen_body,
      parent_content_author: nil,
      parent_content_database_id: nil,
      parent_content_global_relay_id: nil,
      parent_content_created_at: nil,
      parent_content_updated_at: nil,
      owner: serialized_repository_owner,
      repository: serialized_repository,
      content_visibility: serialized_repository[:visibility],
      content_url: serializer.url_for_model(payload[:issue]),
    }

    publish(user_generated_content_msg, schema: "github.platform_health.v1.UserGeneratedContent", publisher: GitHub.user_generated_content_hydro_publisher, topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat

    auto_add_msg = {
      actor_id: serialized_actor[:id],
      repository_id: serialized_repository[:id],
      issue_id: serialized_issue[:id_value]
    }
    publish(auto_add_msg, topic: "github.memex_automation.v0.IssueCreateEvent", schema: "github.memex_automation.v0.AutoAddEvent")

    publish_secret_scanning_issue(payload, serialized_repository, serialized_repository_owner, serialized_actor)

    # Only publish to the following topics if the repository is public.
    next unless payload[:repository].public?

    issue_create_msg = {
      request_context: serialized_request_context,
      actor: serialized_actor,
      repository: serialized_repository,
      repository_owner: serialized_repository_owner,
      issue: serialized_issue,
      issue_creator: serialized_issue_creator,
      title: payload[:issue].title,
      body: payload[:issue].body,
      spamurai_form_signals: serialized_spamurai_form_signals,
      specimen_body: serialized_specimen_body,
      specimen_title: serialized_specimen_title,
    }

    publish(issue_create_msg, schema: "github.v1.IssueCreate", publisher: GitHub.legacy_user_generated_content_publisher, topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("issue.update") do |payload|
    title_change = payload[:previous_title] != payload[:current_title]

    # Skip publishing if the issue is a pull request without a title change.
    next if payload[:issue].pull_request? && !title_change

    serialized_actor, serialized_repository, serialized_repository_owner = T.let(nil, T.untyped)
    ActiveRecord::Base.connected_to(role: :reading) do
      serialized_actor = serializer.user(payload[:actor])
      serialized_repository = serializer.repository(payload[:repository])
      serialized_repository_owner = serializer.user(payload[:repository_owner])
    end

    serialized_spamurai_form_signals = serializer.spamurai_form_signals(GitHub.context[:spamurai_form_signals])
    serialized_specimen_body = serializer.specimen_data(payload[:current_body])
    serialized_specimen_title = serializer.specimen_data(payload[:current_title])
    serialized_issue = serializer.issue(payload[:issue])
    serialized_pull_request = serializer.pull_request(payload[:issue].try(:pull_request))
    serialized_request_context = serializer.request_context(GitHub.context.to_hash)

    base_issue_update_payload = {
      request_context: serialized_request_context,
      actor: serialized_actor,
      repository: serialized_repository,
      repository_owner: serialized_repository_owner,
      issue: serialized_issue,
      previous_title: payload[:previous_title],
      current_title: payload[:current_title],
      previous_body: payload[:previous_body],
      current_body: payload[:current_body],
      spamurai_form_signals: serialized_spamurai_form_signals,
      specimen_body: serialized_specimen_body,
      specimen_title: serialized_specimen_title,
    }

    if title_change
      issue_update_v2_msg = base_issue_update_payload.merge(pull_request: serialized_pull_request)
      publish(issue_update_v2_msg, schema: "github.v2.IssueUpdate", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
    end

    # Only publish the following messages if this Issue is not a Pull Request.
    next if payload[:issue].pull_request?

    user_generated_content_msg = {
      request_context: serialized_request_context,
      spamurai_form_signals: serialized_spamurai_form_signals,
      action_type: :UPDATE,
      content_type: :ISSUE,
      actor: serialized_actor,
      original_type_url: GitHub::Config::HydroConfig.build_type_url("github.v1.IssueUpdate"),
      content_database_id: serialized_issue[:id_value],
      content_global_relay_id: serialized_issue[:global_relay_id],
      content_created_at: serialized_issue[:created_at],
      content_updated_at: serialized_issue[:updated_at],
      title: serialized_specimen_title,
      content: serialized_specimen_body,
      parent_content_author: nil,
      parent_content_database_id: nil,
      parent_content_global_relay_id: nil,
      parent_content_created_at: nil,
      parent_content_updated_at: nil,
      owner: serialized_repository_owner,
      repository: serialized_repository,
      content_visibility: serialized_repository[:visibility],
      content_url: serializer.url_for_model(payload[:issue]),
    }

    publish(user_generated_content_msg, schema: "github.platform_health.v1.UserGeneratedContent", publisher: GitHub.user_generated_content_hydro_publisher, topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat

    auto_add_msg = {
      actor_id: serialized_actor[:id],
      repository_id: serialized_repository[:id],
      issue_id: serialized_issue[:id_value]
    }
    publish(auto_add_msg, topic: "github.memex_automation.v0.IssueUpdateEvent", schema: "github.memex_automation.v0.AutoAddEvent")

    publish_secret_scanning_issue(payload, serialized_repository, serialized_repository_owner, serialized_actor)

    # Only publish to the following topics if the repository is public.
    next unless payload[:repository].public?

    issue_update_v1_msg = base_issue_update_payload.merge(issue_updater: serializer.user(payload[:issue_updater]))

    publish(issue_update_v1_msg, schema: "github.v1.IssueUpdate", publisher: GitHub.legacy_user_generated_content_publisher, topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("issue.events.reopened") do |payload|
    # Only publish if the issue is not a pull request
    next if payload[:issue].pull_request?

    serialized_actor = serializer.user(payload[:actor])
    serialized_issue = serializer.issue(payload[:issue])
    serialized_repository = serializer.repository(payload[:repository])
    issue_msg = {
      actor: serialized_actor,
      issue: serialized_issue,
      repository: serialized_repository,
      repository_owner: serializer.user(payload[:repository_owner]),
    }
    publish(issue_msg, schema: "github.v1.IssueReopen", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("issue.events.closed") do |payload|
    # Only publish if the issue is not a pull request
    next if payload[:issue].pull_request?

    serialized_actor, serialized_repository, serialized_issue_creator = T.let(nil, T.untyped)
    ActiveRecord::Base.connected_to(role: :reading) do
      serialized_actor = serializer.user(payload[:actor])
      serialized_repository = serializer.repository(payload[:repository])
      serialized_issue_creator = serializer.user(payload[:issue].user)
    end

    serialized_issue = serializer.issue(payload[:issue])

    issue_close_msg = {
      actor: serialized_actor,
      issue: serialized_issue,
      repository: serialized_repository,
      repository_owner: serializer.user(payload[:repository_owner]),
      issue_creator: serialized_issue_creator,
    }

    publish(issue_close_msg, schema: "github.v1.IssueClose", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("issue.events.converted_to_discussion") do |payload, _event|
    serialized_actor = serializer.user(payload[:actor])
    serialized_issue = serializer.issue(payload[:issue])
    serialized_repository = serializer.repository(payload[:repository])
    issue_converted_to_discussion_event = {
      actor: serialized_actor,
      issue: serialized_issue,
      repository: serialized_repository
    }

    publish(issue_converted_to_discussion_event, schema: "github.v1.IssueConvertedToDiscussion")
  end

  subscribe(/issue.events.(milestoned|demilestoned)/) do |payload, event|
    issue_msg = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      actor: serializer.user(payload[:actor]),
      repository: serializer.repository(payload[:repository]),
      issue: serializer.issue(payload[:issue]),
      milestone: serializer.milestone(payload[:issue].milestone),
      pull_request: serializer.pull_request(payload[:issue].try(:pull_request)),
      action: event
    }
    publish(issue_msg, schema: "github.v1.IssueUpdateMilestone", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe(/issue.events.(assigned|unassigned)/) do |payload, event|
    issue_msg = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      actor: serializer.user(payload[:actor]),
      repository: serializer.repository(payload[:repository]),
      issue: serializer.issue(payload[:issue]),
      assignees: serializer.users(payload[:assignees]),
      pull_request: serializer.pull_request(payload[:issue].try(:pull_request)),
      action: event,
      assignee: serializer.user(payload[:assignee]),
    }

    if payload[:actor]&.feature_flag_enabled?(:copilot_swe_agent_url_trigger, default: false)
      issue_msg[:event_url] = serializer.url_for_model(payload[:issue])
    end

    publish(issue_msg, schema: "github.v1.IssueUpdateAssignee", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V2 })
  end

  subscribe(/issue.events.(labeled|unlabeled)/) do |payload, event|
    issue_msg = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      actor: serializer.user(payload[:actor]),
      repository: serializer.repository(payload[:repository]),
      repository_owner: serializer.user(payload[:repository_owner]),
      issue: serializer.issue(payload[:issue]),
      labels: serializer.labels(payload[:labels]),
      pull_request: serializer.pull_request(payload[:issue].try(:pull_request)),
      action: event
    }

    publish(issue_msg, schema: "github.v1.IssueUpdateLabel", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V2 })
  end

  subscribe(/issue.(typed|untyped)/) do |payload, event|
    issue_msg = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      actor: serializer.user(payload[:actor]),
      repository: serializer.repository(payload[:repository]),
      issue: serializer.issue(payload[:issue]),
      issue_type: serializer.issue_type(payload[:issue_type]),
      prev_issue_type: payload[:prev_issue_type].present? ? serializer.issue_type(payload[:prev_issue_type]) : nil,
      action: event
    }
    publish(issue_msg, schema: "github.v1.IssueUpdateIssueType")
  end

  subscribe(/issue.issue_field_value.changed/) do |payload|
    operation = if payload[:destroyed]
      :DELETE
    elsif payload[:created]
      :CREATE
    else
      :UPDATE
    end

    issue_msg = {
      actor_id: payload[:actor_id],
      repository_id: payload[:repository].id,
      issue_id: payload[:issue].id,
      issue_field: serializer.issue_field(payload[:issue_field]),
      issue_field_value_id: payload[:issue_field_value].id,
      operation: operation,
      issue_field_option_id: payload[:issue_field_option_id],
      issue_field_prev_option_id: payload[:issue_field_prev_option_id],
    }

    publish(issue_msg, schema: "github.v1.IssueUpdateIssueFieldValue")
  end

  subscribe("issue_field.create") do |payload|
    message = {
      actor: serializer.user(payload[:actor]),
      issue_field: serializer.issue_field(payload[:issue_field]),
    }

    publish(message, schema: "github.v1.IssueFieldCreate")
  end

  subscribe("issue_field_option.create") do |payload|
    message = {
      actor: serializer.user(payload[:actor]),
      issue_field: serializer.issue_field(payload[:issue_field]),
      issue_field_option: serializer.issue_field_option(payload[:issue_field_option]),
    }

    publish(message, schema: "github.v1.IssueFieldOptionCreate")
  end

  subscribe("issue_field_option.update") do |payload|
    message = {
      actor: serializer.user(payload[:actor]),
      issue_field: serializer.issue_field(payload[:issue_field]),
      issue_field_option: serializer.issue_field_option(payload[:issue_field_option]),
    }

    publish(message, schema: "github.v1.IssueFieldOptionUpdate")
  end

  subscribe("issue_field_option.destroy") do |payload|
    message = {
      actor: serializer.user(payload[:actor]),
      issue_field: serializer.issue_field(payload[:issue_field]),
      issue_field_option: serializer.issue_field_option(payload[:issue_field_option]),
    }

    publish(message, schema: "github.v1.IssueFieldOptionDestroy")
  end

  subscribe("issue_type.create") do |payload|
    message = {
      actor: serializer.user(payload[:actor]),
      issue_type: serializer.issue_type(payload[:issue_type]),
    }

    publish(message, schema: "github.v1.IssueTypeCreate")
  end

  subscribe("issue_type.update") do |payload|
    message = {
      actor: serializer.user(payload[:actor]),
      issue_type: serializer.issue_type(payload[:issue_type]),
    }

    publish(message, schema: "github.v1.IssueTypeUpdate")
  end

  subscribe("issue_type.destroy") do |payload|
    message = {
      actor: serializer.user(payload[:actor]),
      issue_type: serializer.issue_type(payload[:issue_type]),
    }

    publish(message, schema: "github.v1.IssueTypeDestroy")
  end

  subscribe("repository_issue_type.create") do |payload|
    message = {
      actor: serializer.user(payload[:actor]),
      repository: serializer.repository(payload[:repository]),
      issue_type: serializer.issue_type(payload[:issue_type]),
      enabled: payload[:enabled],
    }

    publish(message, schema: "github.v1.RepositoryIssueTypeCreate")
  end

  subscribe("repository_issue_type.update") do |payload|
    message = {
      actor: serializer.user(payload[:actor]),
      repository: serializer.repository(payload[:repository]),
      issue_type: serializer.issue_type(payload[:issue_type]),
      enabled: payload[:enabled],
    }

    publish(message, schema: "github.v1.RepositoryIssueTypeUpdate")
  end

  subscribe("repository_issue_type.destroy") do |payload|
    message = {
      actor: serializer.user(payload[:actor]),
      repository: serializer.repository(payload[:repository]),
      issue_type: serializer.issue_type(payload[:issue_type]),
      enabled: payload[:enabled],
    }

    publish(message, schema: "github.v1.RepositoryIssueTypeDestroy")
  end

  subscribe("issue_comment.create") do |payload|
    # Only publish the following messages if this Issue is not a Pull Request.
    next if payload[:issue].pull_request?

    serialized_actor, serialized_repository, serialized_repository_owner, serialized_issue_creator = T.let(nil, T.untyped)
    ActiveRecord::Base.connected_to(role: :reading) do
      serialized_actor = serializer.user(payload[:actor])
      serialized_repository = serializer.repository(payload[:repository])
      serialized_repository_owner = serializer.user(payload[:repository_owner])
      serialized_issue_creator = serializer.user(payload[:issue_creator])
    end

    serialized_spamurai_form_signals = serializer.spamurai_form_signals(GitHub.context[:spamurai_form_signals])
    serialized_specimen_body = serializer.specimen_data(payload[:issue_comment].body)
    serialized_request_context = serializer.request_context(GitHub.context.to_hash)
    serialized_issue = serializer.issue(payload[:issue])
    serialized_issue_comment = serializer.issue_comment(payload[:issue_comment])

    user_generated_content_msg = {
      request_context: serialized_request_context,
      spamurai_form_signals: serialized_spamurai_form_signals,
      action_type: :CREATE,
      content_type: :ISSUE_COMMENT,
      actor: serialized_actor,
      original_type_url: GitHub::Config::HydroConfig.build_type_url("github.v1.IssueCommentCreate"),
      content_database_id: serialized_issue_comment[:id_value],
      content_global_relay_id: serialized_issue_comment[:global_relay_id],
      content_created_at: serialized_issue_comment[:created_at],
      content_updated_at: serialized_issue_comment[:updated_at],
      title: nil,
      content: serialized_specimen_body,
      parent_content_author: serialized_issue_creator,
      parent_content_database_id: serialized_issue[:id_value],
      parent_content_global_relay_id: serialized_issue[:global_relay_id],
      parent_content_created_at: serialized_issue[:created_at],
      parent_content_updated_at: serialized_issue[:updated_at],
      owner: serialized_repository_owner,
      repository: serialized_repository,
      content_visibility: serialized_repository[:visibility],
      content_url: serializer.url_for_model(payload[:issue_comment]),
    }

    conduit_msg = {
      actor: serialized_actor,
      repository: serialized_repository,
      repository_owner: serialized_repository_owner,
      issue: serialized_issue,
      issue_comment: serialized_issue_comment,
    }

    publish(conduit_msg, schema: "github.v1.ConduitIssueCommentCreate")

    publish(user_generated_content_msg, schema: "github.platform_health.v1.UserGeneratedContent", publisher: GitHub.user_generated_content_hydro_publisher, topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat

    publish_secret_scanning_issue_comment(payload, serialized_repository, serialized_repository_owner, serialized_actor)

    # Only publish to the following topics if the repository is public.
    next unless payload[:repository].public?

    message = {
      request_context: serialized_request_context,
      actor: serialized_actor,
      repository: serialized_repository,
      repository_owner: serialized_repository_owner,
      issue: serialized_issue,
      issue_creator: serialized_issue_creator,
      issue_comment: serialized_issue_comment,
      body: payload[:issue_comment].body,
      spamurai_form_signals: serialized_spamurai_form_signals,
      specimen_body: serialized_specimen_body,
    }

    publish(message, schema: "github.v1.IssueCommentCreate", publisher: GitHub.legacy_user_generated_content_publisher, topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("issue_comment.update") do |payload|
    # Only publish the following messages if this Issue is not a Pull Request.
    next if payload[:issue].pull_request?

    serialized_actor, serialized_repository, serialized_repository_owner, serialized_issue_creator = T.let(nil, T.untyped)
    ActiveRecord::Base.connected_to(role: :reading) do
      serialized_actor = serializer.user(payload[:actor])
      serialized_repository = serializer.repository(payload[:repository])
      serialized_repository_owner = serializer.user(payload[:repository_owner])
      serialized_issue_creator = serializer.user(payload[:issue_creator])
    end

    serialized_spamurai_form_signals = serializer.spamurai_form_signals(GitHub.context[:spamurai_form_signals])
    serialized_specimen_body = serializer.specimen_data(payload[:issue_comment].body)
    serialized_request_context = serializer.request_context(GitHub.context.to_hash)
    serialized_issue = serializer.issue(payload[:issue])
    serialized_issue_comment = serializer.issue_comment(payload[:issue_comment])

    user_generated_content_msg = {
      request_context: serialized_request_context,
      spamurai_form_signals: serialized_spamurai_form_signals,
      action_type: :UPDATE,
      content_type: :ISSUE_COMMENT,
      actor: serialized_actor,
      original_type_url: GitHub::Config::HydroConfig.build_type_url("github.v1.IssueCommentUpdate"),
      content_database_id: serialized_issue_comment[:id_value],
      content_global_relay_id: serialized_issue_comment[:global_relay_id],
      content_created_at: serialized_issue_comment[:created_at],
      content_updated_at: serialized_issue_comment[:updated_at],
      title: nil,
      content: serialized_specimen_body,
      parent_content_author: serialized_issue_creator,
      parent_content_database_id: serialized_issue[:id_value],
      parent_content_global_relay_id: serialized_issue[:global_relay_id],
      parent_content_created_at: serialized_issue[:created_at],
      parent_content_updated_at: serialized_issue[:updated_at],
      owner: serialized_repository_owner,
      repository: serialized_repository,
      content_visibility: serialized_repository[:visibility],
      content_url: serializer.url_for_model(payload[:issue_comment]),
    }

    publish(user_generated_content_msg, schema: "github.platform_health.v1.UserGeneratedContent", publisher: GitHub.user_generated_content_hydro_publisher, topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat

    publish_secret_scanning_issue_comment(payload, serialized_repository, serialized_repository_owner, serialized_actor)

    # Only publish to the following topics if the repository is public.
    next unless payload[:repository].public?

    message = {
      request_context: serialized_request_context,
      actor: serialized_actor,
      repository: serialized_repository,
      repository_owner: serialized_repository_owner,
      issue: serialized_issue,
      issue_creator: serialized_issue_creator,
      issue_comment: serialized_issue_comment,
      spamurai_form_signals: serialized_spamurai_form_signals,
      current_specimen_body: serialized_specimen_body,
      previous_specimen_body: serializer.specimen_data(payload[:previous_body])
    }

    publish(message, schema: "github.v1.IssueCommentUpdate", publisher: GitHub.legacy_user_generated_content_publisher, topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe(/issue_comment\.(pinned|unpinned)/) do |payload|
    message = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      actor: serializer.user(payload[:actor]),
      state: payload[:state],
      issue_comment: serializer.issue_comment(payload[:issue_comment]),
      issue: serializer.issue(payload[:issue]),
      repository: serializer.repository(payload[:repository]),
    }

    publish(message, schema: "github.v1.IssueCommentPinUpdated", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("issue_links.create") do |payload|
    message = {
      actor: serializer.user(payload[:actor]),
      source_repository: serializer.repository(payload[:source_repository]),
      source_issue: serializer.issue(payload[:source_issue]),
      target_repository: serializer.repository(payload[:target_repository]),
      target_issue: serializer.issue(payload[:target_issue]),
      link_type: payload[:link_type],
      new_target_issue: payload[:new_target_issue],
    }

    publish(message, schema: "github.v1.IssueLinkCreate", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("issue_links.delete") do |payload|
    message = {
      actor: serializer.user(payload[:actor]),
      source_repository: serializer.repository(payload[:source_repository]),
      source_issue: serializer.issue(payload[:source_issue]),
      target_repository: serializer.repository(payload[:target_repository]),
      target_issue: serializer.issue(payload[:target_issue]),
      link_type: payload[:link_type],
    }

    publish(message, schema: "github.v1.IssueLinkDelete", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("issue.pr_connected") do |payload|
    message = {
      actor: serializer.user(payload[:actor]),
      issue_repository: serializer.repository(payload[:issue_repository]),
      issue: serializer.issue(payload[:issue]),
      pull_request: serializer.pull_request(payload[:pull_request]),
      pull_request_author: serializer.user(payload[:pull_request_author]),
      source: payload[:source],
    }

    publish(message, schema: "github.v1.CloseIssueReferenceConnected")
  end

  subscribe("issue.pr_disconnected") do |payload|
    message = {
      actor: serializer.user(payload[:actor]),
      issue_repository: serializer.repository(payload[:issue_repository]),
      issue: serializer.issue(payload[:issue]),
      pull_request: serializer.pull_request(payload[:pull_request]),
      pull_request_author: serializer.user(payload[:pull_request_author]),
      source: payload[:source],
    }

    publish(message, schema: "github.v1.CloseIssueReferenceDisconnected")
  end

  subscribe("issue.deleted") do |payload|
    message = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      repository: serializer.repository(payload[:repository]),
      actor: serializer.user(payload[:actor]),
      issue: serializer.issue(payload[:issue]),
    }
    publish(message, schema: "github.v1.IssueDeleted", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("issue.transferred") do |payload|
    message = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      old_repository: serializer.repository(payload[:old_repository]),
      old_issue: serializer.issue(payload[:old_issue]),
      new_repository: serializer.repository(payload[:new_repository]),
      new_issue: serializer.issue(payload[:new_issue]),
      actor: serializer.user(payload[:actor]),
    }
    publish(message, schema: "github.v1.IssueTransferred")
  end

  subscribe(/issue\.(pinned|unpinned)/) do |payload|
    message = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      repository: serializer.repository(payload[:repository]),
      actor: serializer.user(payload[:actor]),
      state: payload[:state],
      issue: serializer.issue(payload[:issue]),
    }
    publish(message, schema: "github.v1.IssuePinUpdated", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("browser.issue-hovercard-hover") do |payload|
    issue = Issue.find_by(id: payload[:pullRequestOrIssueId]) # domain-isolation-query-violation:ignore:packages/issues (SELECT)

    message = {
      actor: serializer.user(payload[:client][:user]),
      request_context: serializer.request_context(GitHub.context.to_hash,
        overrides: browser_request_context_overrides(payload)),
      issue: serializer.issue(issue),
      context: serializer.hovercard_context_string(payload[:subject]),
    }

    publish(message, schema: "github.v1.IssueHovercardHover", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("browser.convert_task_to_issue.click") do |payload|
    message = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      actor: serializer.user(User.find_by(id: payload[:user_id])),
      target_type: payload[:target_type].upcase.to_sym,
      repository: serializer.repository(payload[:repository]),
      repository_owner: serializer.user(payload[:repository_owner]),
      tracking_issue: serializer.issue(payload[:tracking_issue]),
      title: payload[:title],
      issue_id: payload[:issue_id],
      issue_id_value: payload[:issue_id],
    }
    publish(message, schema: "github.v1.ConvertTaskToIssueClick", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("browser.issue_cross_references.click") do |payload|
    message = {
      actor: serializer.user(User.find_by(id: payload[:user_id])),
      issue: serializer.issue(Issue.find_by(id: payload[:issue_id])), # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      pull_request: serializer.pull_request(PullRequest.find_by(id: payload[:pull_request_id])),
      reference_location: payload[:reference_location],
      request_context: serializer.request_context(GitHub.context.to_hash),
    }
    publish(message, schema: "github.v1.IssueClosedByXrefsClick", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("browser.issue_timeline_filter_menu.click") do |payload|
    message = {
      actor: serializer.user(User.find_by(id: payload[:user_id])),
      issue: serializer.issue(Issue.find_by(id: payload[:issue_id])), # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      filter_selection: payload[:filter_selection],
      request_context: serializer.request_context(GitHub.context.to_hash),
    }
    publish(message, schema: "github.v1.IssueTimelineFilterClick", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("label.create") do |payload|
    message = {
      actor: serializer.user(payload[:actor]),
      label: serializer.label(payload[:label]),
      issue_id: payload[:issue_id],
    }

    publish(message, schema: "github.v1.LabelCreate", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("label.update") do |payload|
    message = {
      actor: serializer.user(payload[:actor]),
      label: serializer.label(payload[:label]),
    }

    publish(message, schema: "github.v1.LabelUpdate", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("label.delete") do |payload|
    message = {
      actor: serializer.user(payload[:actor]),
      label: serializer.label(payload[:label]),
    }

    publish(message, schema: "github.v1.LabelDelete", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("browser.blank_issue.click") do |payload|
    repository = if FeatureFlag.vexi.enabled?(:repos_by_id_config, default: false)
      Repositories.domain.by_id(payload[:repository_id])
    else
      Repository.find_by(id: payload[:repository_id])
    end

    message = {
      actor: serializer.user(User.find_by(id: payload[:actor_id])),
      repository: serializer.repository(repository),
      request_context: serializer.request_context(GitHub.context.to_hash),
      blank_issue_clicked: payload[:blank_issue_clicked],
    }

    publish(message, schema: "github.v1.BlankIssueClick", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("browser.contact_link.click") do |payload|
    repository = if FeatureFlag.vexi.enabled?(:repos_by_id_config, default: false)
      Repositories.domain.by_id(payload[:repository_id])
    else
      Repository.find_by(id: payload[:repository_id])
    end

    message = {
      actor: serializer.user(User.find_by(id: payload[:actor_id])),
      repository: serializer.repository(repository),
      request_context: serializer.request_context(GitHub.context.to_hash),
      contact_link: serializer.contact_link(payload[:contact_link]),
    }

    publish(message, schema: "github.v1.ContactLinkClick", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  def publish_secret_scanning_issue(payload, serialized_repository, serialized_repository_owner, serialized_actor)
    T.bind(self, Hydro::EventForwarder)

    contents = []
    issue = payload[:issue]
    begin
      content_scanning = SecretScanning::Features::Repo::ContentScanning.new(payload[:repository])
      if content_scanning.enabled?
        encrypted_title = SecretScanning::Encryption::EncryptedUserContentHelper.encrypt_user_content(issue.title, issue.id, issue.created_at)
        if encrypted_title.nil?
          GitHub.logger.error(
            "Could not publish issue title for secret scanning",
            "code.namespace": self.class.name,
            "code.function": "publish_secret_scanning_issue",
            "gh.issue.id": issue.id,
          )
        else
          contents.push({ content_type: :ISSUE_TITLE, content: encrypted_title })
        end

        encrypted_body = SecretScanning::Encryption::EncryptedUserContentHelper.encrypt_user_content(issue.body, issue.id, issue.created_at)
        if encrypted_body.nil?
          GitHub.logger.error(
            "Could not publish issue body for secret scanning",
            "code.namespace": self.class.name,
            "code.function": "publish_secret_scanning_issue",
            "gh.issue.id": issue.id,
          )
        else
          contents.push({ content_type: :ISSUE_BODY, content: encrypted_body })
        end

        scan_msg = {
          repository: serialized_repository,
          owner: serialized_repository_owner,
          actor: serialized_actor,
          content_id: issue.id,
          content_number: issue.number,
          feature_flags: SecretScanning::Instrumentation::RepositoryServiceFlags.new(payload[:repository]).issue_scanning_service_flags,
          content_created_at: issue.created_at ? issue.created_at.getutc : nil,
          contents: contents
        }
        publish(scan_msg, topic: "github.secret_scanning.v1.IssueScan", schema: "github.secret_scanning.v1.EncryptedContentScanEvent")
      end
    rescue StandardError => e
      # Prevent secret scanning errors from impacting other teams
      Failbot.report(e)
      GitHub.logger.error(
        "Sending Issue Scanning message failed",
        "code.namespace": self.class.name,
        "code.function": "publish_secret_scanning_issue_create",
        "exception.message": e.message,
      )
    end
  end

  def publish_secret_scanning_issue_comment(payload, serialized_repository, serialized_repository_owner, serialized_actor)
    T.bind(self, Hydro::EventForwarder)

    contents = []
    comment = payload[:issue_comment]
    begin
      content_scanning = SecretScanning::Features::Repo::ContentScanning.new(payload[:repository])
      if content_scanning.enabled?
        encrypted_body = SecretScanning::Encryption::EncryptedUserContentHelper.encrypt_user_content(comment.body, comment.id, comment.created_at)
        contents.push({ content_type: :ISSUE_COMMENT, content: encrypted_body }) unless encrypted_body.nil?

        scan_msg = {
          repository: serialized_repository,
          owner: serialized_repository_owner,
          actor: serialized_actor,
          content_id: comment.id,
          content_number: payload[:issue].number,
          feature_flags: SecretScanning::Instrumentation::RepositoryServiceFlags.new(payload[:repository]).issue_scanning_service_flags,
          content_created_at: comment.created_at ? comment.created_at.getutc : nil,
          contents: contents
        }
        publish(scan_msg, topic: "github.secret_scanning.v1.IssueCommentScan", schema: "github.secret_scanning.v1.EncryptedContentScanEvent")
      end
    rescue StandardError => e
      # Prevent secret scanning errors from impacting other teams
      Failbot.report(e)
      GitHub.logger.error(
        "Sending Issue Scanning message failed",
        "code.namespace": self.class.name,
        "code.function": "issue_comment.update",
        "exception.message": e.message,
      )
    end
  end

  subscribe("issues_react_feedback") do |payload|
    message = {
      rating: serializer.issues_react_feedback_rating(payload[:rating]),
      content: serializer.issues_react_feedback_content(payload[:content]),
      request_context: serializer.request_context(payload[:request_context])
    }

    publish(message, schema: "hydro.schemas.github.issues.v0.IssuesReactFeedback")
  end

  def similar_issues_feedback_rating(rating)
    case rating
    when "positive" then :POSITIVE
    when "negative" then :NEGATIVE
    else :UNKNOWN
    end
  end

  subscribe("similar_issues_issues_create_feedback") do |payload|
    message = {
      rating: similar_issues_feedback_rating(payload[:rating]),
      repository: serializer.repository(payload[:repository]),
      repository_owner: serializer.user(payload[:repository_owner]),
      request_context: serializer.request_context(payload[:request_context]),
      session_id: payload[:session_id]
    }

    publish(message, schema: "hydro.schemas.github.v0.SimilarIssuesIssuesCreateFeedback")
  end

  subscribe("issue_link_batch.create") do |payload|
    message = {
      actor: serializer.user(payload[:actor]),
      source_repository: serializer.repository(payload[:source_repository]),
      source_issue: serializer.issue(payload[:source_issue]),
      total_issue_links: payload[:total_issue_links],
      xrepo_issue_links: payload[:xrepo_issue_links],
      link_type: payload[:link_type]
    }

    publish(message, schema: "github.v1.IssueLinkBatchCreate", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("issue_link_batch.delete") do |payload|
    message = {
      actor: serializer.user(payload[:actor]),
      source_repository: serializer.repository(payload[:source_repository]),
      source_issue: serializer.issue(payload[:source_issue]),
      total_issue_links: payload[:total_issue_links],
      xrepo_issue_links: payload[:xrepo_issue_links],
      link_type: payload[:link_type]
    }

    publish(message, schema: "github.v1.IssueLinkBatchDelete", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  # Maps the integer confidence score persisted on the intent row to the
  # `IssueUpdateIntent.ConfidenceLevel` enum value declared in the proto.
  def issue_update_intent_confidence_level(score)
    case score
    when Issues::ConfidenceThreshold::Level::LOW.score then :LOW
    when Issues::ConfidenceThreshold::Level::MEDIUM.score then :MEDIUM
    when Issues::ConfidenceThreshold::Level::HIGH.score then :HIGH
    else :UNKNOWN
    end
  end

  # Maps the model's string state to the `IssueUpdateIntent.State` enum.
  # `nil` represents "no previous state" on a creation event and is encoded
  # as STATE_UNKNOWN per the proto contract.
  def issue_update_intent_state(state)
    case state
    when Issues::UpdateIntent::STATE_PENDING then :PENDING
    when Issues::UpdateIntent::STATE_APPLIED then :APPLIED
    when Issues::UpdateIntent::STATE_APPROVED then :APPROVED
    when Issues::UpdateIntent::STATE_DISMISSED then :DISMISSED
    else :STATE_UNKNOWN
    end
  end

  # Parses a timestamp value carried on the instrumentation payload back to
  # a `Time`. The `Issues::UpdateIntent` KV backing serializes timestamps as
  # ISO 8601 strings; protobuf `Timestamp` fields require a `Time` (or
  # numeric).
  def issue_update_intent_timestamp(value)
    case value
    when nil then nil
    when Time then value
    when String
      begin
        Time.iso8601(value)
      rescue ArgumentError
        nil
      end
    end
  end

  # Builds the message published to the `github.v1.IssueUpdateIntent` topic
  # from a Global Instrumenter payload emitted by `Issues::UpdateIntent`.
  # Reads run inside `connected_to(role: :reading)` so we don't promote the
  # request to the writer.
  def issue_update_intent_message(payload)
    T.bind(self, Hydro::EventForwarder)

    issue, repository, actor, repository_owner, resolved_by, suggested_label, suggested_issue_type =
      T.let(nil, T.untyped)
    ActiveRecord::Base.connected_to(role: :reading) do
      issue = Issue.find_by(id: payload[:issue_id])
      repository = issue&.repository || Repository.find_by(id: payload[:repository_id])
      actor = payload[:actor_id] ? User.find_by(id: payload[:actor_id]) : nil
      repository_owner = repository&.owner
      resolved_by = payload[:resolved_by_id] ? User.find_by(id: payload[:resolved_by_id]) : nil

      case payload[:action]
      when "set_labels"
        if payload[:target_id] && repository
          suggested_label = repository.labels.find_by(id: payload[:target_id])
        end
      when "set_type"
        if payload[:target_value] && repository_owner
          suggested_issue_type = IssueType.find_by(owner: repository_owner, name: payload[:target_value])
        end
      end
    end

    repository_threshold = if repository
      issue_update_intent_confidence_level(Issues::ConfidenceThreshold.get_threshold(repository))
    else
      :UNKNOWN
    end

    suggestion_confidence = issue_update_intent_confidence_level(payload[:confidence_score])

    suggested_labels = if suggested_label
      [{
        label: serializer.label(suggested_label),
        rationale: payload[:rationale],
        confidence: suggestion_confidence,
      }]
    else
      []
    end

    suggested_field_values = if payload[:action] == "set_field" && payload[:target_id]
      [{
        field_value: { issue_field_id: payload[:target_id] },
        rationale: payload[:rationale],
        confidence: suggestion_confidence,
      }]
    else
      []
    end

    {
      actor: serializer.user(actor),
      repository: serializer.repository(repository),
      issue: serializer.issue(issue),
      pull_request: serializer.pull_request(issue&.pull_request),
      repository_owner: serializer.user(repository_owner),
      request_context: serializer.request_context(GitHub.context.to_hash),
      repository_confidence_threshold: repository_threshold,
      is_suggestion: payload[:current_state] == Issues::UpdateIntent::STATE_PENDING ||
        payload[:previous_state] == Issues::UpdateIntent::STATE_PENDING,
      suggested_issue_type: serializer.issue_type(suggested_issue_type),
      suggested_labels: suggested_labels,
      suggested_field_values: suggested_field_values,
      intent_id: payload[:intent_id],
      action: payload[:action],
      previous_state: issue_update_intent_state(payload[:previous_state]),
      current_state: issue_update_intent_state(payload[:current_state]),
      rationale: payload[:rationale],
      target_id: payload[:target_id],
      target_value: payload[:target_value],
      issue_event_id: payload[:issue_event_id],
      resolved_by: serializer.user(resolved_by),
      created_at: issue_update_intent_timestamp(payload[:created_at]),
      updated_at: issue_update_intent_timestamp(payload[:updated_at]),
      confidence: suggestion_confidence,
    }
  end

  subscribe("issues.update_intent.create") do |payload|
    publish(issue_update_intent_message(payload), schema: "github.v1.IssueUpdateIntent")
  end

  subscribe("issues.update_intent.transition") do |payload|
    publish(issue_update_intent_message(payload), schema: "github.v1.IssueUpdateIntent")
  end
end
