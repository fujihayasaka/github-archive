# frozen_string_literal: true

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("security_campaigns.security_campaign_create") do |payload|
    serialized_actor = serializer.user(payload[:actor])
    serialized_request_context = serializer.request_context(GitHub.context.to_hash)

    message = {
      actor: serialized_actor,
      request_context: serialized_request_context,
      repo_count: payload[:repo_count],
      alert_count: payload[:alert_count],
      organization: serializer.organization(payload[:security_campaign].organization),
      description: payload[:security_campaign].description,
      security_campaign: serialized_campaign(payload[:security_campaign]),
      user_managers: payload[:security_campaign].user_manager_users.map { |user| serializer.user(user) },
      team_managers: payload[:security_campaign].team_manager_teams.map { |user| serializer.team(user) },
      source_campaign_id: payload[:source_campaign_id],
    }

    user_generated_content_msg = {
      request_context: serialized_request_context,
      spamurai_form_signals: serializer.spamurai_form_signals(GitHub.context[:spamurai_form_signals]),
      action_type: :CREATE,
      content_type: :SECURITY_CAMPAIGN,
      actor: serialized_actor,
      original_type_url: GitHub::Config::HydroConfig.build_type_url("github.security_campaigns.v0.SecurityCampaignCreate"),
      content_database_id: payload[:security_campaign].id,
      content_global_relay_id: payload[:security_campaign].global_relay_id,
      content_created_at: payload[:security_campaign].created_at,
      content_updated_at: payload[:security_campaign].updated_at,
      title: serializer.specimen_data(payload[:security_campaign].name),
      content: serializer.specimen_data(payload[:security_campaign].description),
      parent_content_author: nil,
      parent_content_database_id: nil,
      parent_content_global_relay_id: nil,
      parent_content_created_at: nil,
      parent_content_updated_at: nil,
      owner: serializer.user(payload[:security_campaign].organization),
      repository: nil,
      content_visibility: :PRIVATE,
      content_url: serializer.url_for_model(payload[:security_campaign]),
    }
    publish(user_generated_content_msg, schema: "github.platform_health.v1.UserGeneratedContent", publisher: GitHub.user_generated_content_hydro_publisher, topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat

    publish(message, schema: "github.security_campaigns.v0.SecurityCampaignCreate")
  end

  subscribe("security_campaigns.security_campaign_delete") do |payload|
    message = {
      actor: serializer.user(payload[:actor]),
      request_context: serializer.request_context(GitHub.context.to_hash),
      organization: serializer.organization(payload[:security_campaign].organization),
      security_campaign: serialized_campaign(payload[:security_campaign]),
      user_managers: payload[:security_campaign].user_manager_users.map { |user| serializer.user(user) },
      team_managers: payload[:security_campaign].team_manager_teams.map { |user| serializer.team(user) },
    }

    publish(message, schema: "github.security_campaigns.v0.SecurityCampaignDelete")
  end

  subscribe("security_campaigns.security_campaign_update") do |payload|
    serialized_actor = serializer.user(payload[:actor])
    serialized_request_context = serializer.request_context(GitHub.context.to_hash)

    message = {
      actor: serialized_actor,
      request_context: serialized_request_context,
      organization: serializer.organization(payload[:security_campaign].organization),
      security_campaign: serialized_campaign(payload[:security_campaign]),
      user_managers: payload[:security_campaign].user_manager_users.map { |user| serializer.user(user) },
      team_managers: payload[:security_campaign].team_manager_teams.map { |user| serializer.team(user) },
      query_changed: payload[:query_changed] ? payload[:query_changed] : false,
    }

    user_generated_content_msg = {
      request_context: serialized_request_context,
      spamurai_form_signals: serializer.spamurai_form_signals(GitHub.context[:spamurai_form_signals]),
      action_type: :UPDATE,
      content_type: :SECURITY_CAMPAIGN,
      actor: serialized_actor,
      original_type_url: GitHub::Config::HydroConfig.build_type_url("github.security_campaigns.v0.SecurityCampaignUpdate"),
      content_database_id: payload[:security_campaign].id,
      content_global_relay_id: payload[:security_campaign].global_relay_id,
      content_created_at: payload[:security_campaign].created_at,
      content_updated_at: payload[:security_campaign].updated_at,
      title: serializer.specimen_data(payload[:security_campaign].name),
      content: serializer.specimen_data(payload[:security_campaign].description),
      parent_content_author: nil,
      parent_content_database_id: nil,
      parent_content_global_relay_id: nil,
      parent_content_created_at: nil,
      parent_content_updated_at: nil,
      owner: serializer.user(payload[:security_campaign].organization),
      repository: nil,
      content_visibility: :PRIVATE,
      content_url: serializer.url_for_model(payload[:security_campaign]),
    }
    publish(user_generated_content_msg, schema: "github.platform_health.v1.UserGeneratedContent", publisher: GitHub.user_generated_content_hydro_publisher, topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat

    publish(message, schema: "github.security_campaigns.v0.SecurityCampaignUpdate")
  end

  subscribe("security_campaigns.security_campaign_publish_draft") do |payload|
    serialized_actor = serializer.user(payload[:actor])
    serialized_request_context = serializer.request_context(GitHub.context.to_hash)

    message = {
      actor: serialized_actor,
      request_context: serialized_request_context,
      organization: serializer.organization(payload[:security_campaign].organization),
      security_campaign: serialized_campaign(payload[:security_campaign]),
      user_managers: payload[:security_campaign].user_manager_users.map { |user| serializer.user(user) },
      team_managers: payload[:security_campaign].team_manager_teams.map { |user| serializer.team(user) },
      source_campaign_id: payload[:source_campaign_id],
    }

    user_generated_content_msg = {
      request_context: serialized_request_context,
      spamurai_form_signals: serializer.spamurai_form_signals(GitHub.context[:spamurai_form_signals]),
      action_type: :UPDATE,
      content_type: :SECURITY_CAMPAIGN,
      actor: serialized_actor,
      original_type_url: GitHub::Config::HydroConfig.build_type_url("github.security_campaigns.v0.SecurityCampaignPublishDraft"),
      content_database_id: payload[:security_campaign].id,
      content_global_relay_id: payload[:security_campaign].global_relay_id,
      content_created_at: payload[:security_campaign].created_at,
      content_updated_at: payload[:security_campaign].updated_at,
      title: serializer.specimen_data(payload[:security_campaign].name),
      content: serializer.specimen_data(payload[:security_campaign].description),
      parent_content_author: nil,
      parent_content_database_id: nil,
      parent_content_global_relay_id: nil,
      parent_content_created_at: nil,
      parent_content_updated_at: nil,
      owner: serializer.user(payload[:security_campaign].organization),
      repository: nil,
      content_visibility: :PRIVATE,
      content_url: serializer.url_for_model(payload[:security_campaign]),
    }

    publish(user_generated_content_msg, schema: "github.platform_health.v1.UserGeneratedContent", publisher: GitHub.user_generated_content_hydro_publisher, topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat

    publish(message, schema: "github.security_campaigns.v0.SecurityCampaignPublishDraft")
  end

  subscribe("security_campaigns.security_campaign_close") do |payload|
    message = {
      actor: serializer.user(payload[:actor]),
      request_context: serializer.request_context(GitHub.context.to_hash),
      organization: serializer.organization(payload[:security_campaign].organization),
      security_campaign: serialized_campaign(payload[:security_campaign]),
      user_managers: payload[:security_campaign].user_manager_users.map { |user| serializer.user(user) },
      team_managers: payload[:security_campaign].team_manager_teams.map { |user| serializer.team(user) },
    }

    publish(message, schema: "github.security_campaigns.v0.SecurityCampaignClose")
  end

  subscribe("security_campaigns.security_campaign_reopen") do |payload|
    message = {
      actor: serializer.user(payload[:actor]),
      request_context: serializer.request_context(GitHub.context.to_hash),
      organization: serializer.organization(payload[:security_campaign].organization),
      security_campaign: serialized_campaign(payload[:security_campaign]),
      user_managers: payload[:security_campaign].user_manager_users.map { |user| serializer.user(user) },
      team_managers: payload[:security_campaign].team_manager_teams.map { |user| serializer.team(user) },
    }

    publish(message, schema: "github.security_campaigns.v0.SecurityCampaignReopen")
  end

  subscribe("security_campaigns.security_campaign_autofix_generation_complete") do |payload|
    message = {
      organization: serializer.organization(payload[:security_campaign].organization),
      security_campaign: serialized_campaign(payload[:security_campaign]),
      duration: payload[:duration],
      alerts: payload[:alerts],
    }

    publish(message, schema: "github.security_campaigns.v0.SecurityCampaignAutofixGenerationComplete")
  end

  subscribe("security_campaigns.security_campaign_autofix_generation_incomplete") do |payload|
    message = {
      organization: serializer.organization(payload[:security_campaign].organization),
      security_campaign: serialized_campaign(payload[:security_campaign]),
      alerts: payload[:alerts],
    }

    publish(message, schema: "github.security_campaigns.v0.SecurityCampaignAutofixGenerationIncomplete")
  end

  def serialized_campaign(campaign)
    {
      id: campaign.id,
      number: campaign.number,
      name: campaign.name,
      organization_id: campaign.organization_id,
      due_date: campaign.ends_at,
      created_at: campaign.created_at,
      updated_at: campaign.updated_at,
      closed_at: campaign.closed_at,
      published_at: campaign.published_at,
      creation_query: campaign.creation_query,
      created_by_id: campaign.created_by_id,
    }
  end
end
