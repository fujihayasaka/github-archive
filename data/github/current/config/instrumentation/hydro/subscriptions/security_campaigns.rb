# frozen_string_literal: true

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("security_campaigns.security_campaign_create") do |payload|
    message = {
      actor: serializer.user(payload[:actor]),
      request_context: serializer.request_context(GitHub.context.to_hash),
      query: payload[:security_campaign].creation_query,
      repo_count: payload[:repo_count],
      alert_count: payload[:alert_count],
      organization: serializer.organization(payload[:security_campaign].organization),
      description: payload[:security_campaign].description,
      security_campaign: serialized_campaign(payload[:security_campaign]),
      user_managers: payload[:security_campaign].user_manager_users.map { |user| serializer.user(user) },
      team_managers: payload[:security_campaign].team_manager_teams.map { |user| serializer.team(user) },
      source_campaign_id: payload[:source_campaign_id],
    }

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
    }
  end
end
