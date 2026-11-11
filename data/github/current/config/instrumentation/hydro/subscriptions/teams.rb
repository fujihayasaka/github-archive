# typed: true
# frozen_string_literal: true

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("team.create") do |payload|
    message = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      actor: serializer.user(payload[:actor]),
      organization: serializer.organization(payload[:organization]),
      team: serializer.team(payload[:team]),
      name: payload[:name],
      business: payload[:business],
      type: payload[:type],
    }

    publish(message, schema: "github.v1.TeamCreate", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("team.update") do |payload|
    message = {
      actor: serializer.user(payload[:actor]),
      team: serializer.team(payload[:team]),
      previous_name: payload[:previous_name],
      previous_description: payload[:previous_description],
      previous_privacy: payload[:previous_privacy],
    }

    publish(message, schema: "github.team.v1.Update")
  end

  subscribe("team.rename") do |payload|
    message = {
      team: serializer.team(payload[:team]),
      previous_name: payload[:previous_name],
      current_name: payload[:current_name],
      actor: serializer.user(payload[:actor]),
    }

    publish(message, schema: "github.v1.TeamRename")
  end

  subscribe("team.destroy") do |payload|
    message = {
      actor: serializer.user(payload[:actor]),
      organization: serializer.organization(payload[:organization]),
      team: serializer.team(payload[:team]),
      business: serializer.business(payload[:business]),
      type: payload[:type],
    }

    publish(message, schema: "github.v1.TeamDestroy")
  end

  subscribe("team.add_members") do |payload|
    message = {
      team: serializer.team(payload[:team]),
      actor: serializer.user(payload[:actor]),
      user_ids: payload[:user_ids],
    }

    publish(message, schema: "github.team.v1.AddMembers")
  end

  subscribe("team.remove_members") do |payload|
    message = {
      team: serializer.team(payload[:team]),
      actor: serializer.user(payload[:actor]),
      user_ids: payload[:user_ids],
    }

    publish(message, schema: "github.team.v1.RemoveMembers")
  end

  subscribe("business_team.add_to_organizations") do |payload|
    business_team = payload[:business_team]
    organization_ids = payload[:organization_ids]
    business = payload[:business]

    message = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      business_id: business.id,
      team_id: business_team.id,
      organization_ids: organization_ids,
      changed_at: Google::Protobuf::Timestamp.new(seconds: Time.current.to_i),
      customer_id: business.customer.id,
    }

    publish(message, schema: "github.team.v1.AddToOrganizations")
  end

  subscribe("business_team.remove_from_organizations") do |payload|
    business_team = payload[:business_team]
    organization_ids = payload[:organization_ids]
    business = payload[:business]

    message = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      business_id: business.id,
      team_id: business_team.id,
      organization_ids: organization_ids,
      changed_at: Google::Protobuf::Timestamp.new(seconds: Time.current.to_i),
      customer_id: business.customer.id,
    }

    publish(message, schema: "github.team.v1.RemoveFromOrganizations")
  end

  subscribe("team_sync_tenant.status_change") do |payload|
    message = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      actor: serializer.user(payload[:actor]),
      organization: serializer.organization(payload[:organization]),
      team_sync_tenant: serializer.team_sync_tenant(payload[:team_sync_tenant]),
      previous_status: serializer.team_sync_tenant_status_mapping(payload[:previous_status]),
      current_status: serializer.team_sync_tenant_status_mapping(payload[:current_status]),
    }
    publish(message, schema: "github.v1.TeamSyncTenantStatusChange", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("team_group_mapping.update") do |payload|
    message = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      actor: serializer.user(payload[:actor]),
      team: serializer.team(payload[:team]),
      organization: serializer.organization(payload[:organization]),
      team_sync_tenant: serializer.team_sync_tenant(payload[:team_sync_tenant]),
      current_mappings: Array(payload[:current_mappings]).map { |mapping| serializer.team_group_mapping(mapping) },
      previous_group_ids: Array(payload[:previous_group_ids]),
    }
    publish(message, schema: "github.v1.TeamGroupMappingUpdate", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("browser.team-hovercard-hover") do |payload|
    team = Team.find_by(id: payload[:teamId])

    message = {
      actor: serializer.user(payload[:client][:user]),
      request_context: serializer.request_context(GitHub.context.to_hash,
        overrides: browser_request_context_overrides(payload)),
      team: serializer.team(team),
      context: serializer.hovercard_context_string(payload[:subject]),
    }

    publish(message, schema: "github.v1.TeamHovercardHover", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end
end
