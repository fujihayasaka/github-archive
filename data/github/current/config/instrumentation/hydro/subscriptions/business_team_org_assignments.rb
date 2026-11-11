# typed: strict
# frozen_string_literal: true

# Hydro event subscriptions for Business Team organization assignments
# This publishes events that Licensify consumes to manage indirect Copilot enablements
Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  # Event: Business Team added to organization(s)
  subscribe("business_team.add_to_organization") do |payload|
    business_team = payload[:business_team]
    organization = payload[:org]
    business = payload[:business]

    next unless business_team && organization && business

    message = ActiveRecord::Base.connected_to(role: :reading) do
      {
        request_context: serializer.request_context(GitHub.context.to_hash),
        business_id: business.id,
        business_team_id: business_team.id,
        org_id: organization.id,
        assigned_to_all_orgs: false,  # This event is for specific org assignment
        is_assigned: true,
        changed_at: Google::Protobuf::Timestamp.new(seconds: Time.current.to_i),
      }
    end

    publish(
      message,
      key: "#{business.customer.id}:#{business_team.id}",
      schema: "github.v1.BusinessTeamOrgAssignmentChanged",
    )
  end

  # Event: Business Team removed from organization(s)
  subscribe("business_team.remove_from_organization") do |payload|
    business_team = payload[:business_team]
    organization = payload[:org]
    business = payload[:business]

    next unless business_team && organization && business

    message = ActiveRecord::Base.connected_to(role: :reading) do
      {
        request_context: serializer.request_context(GitHub.context.to_hash),
        business_id: business.id,
        business_team_id: business_team.id,
        org_id: organization.id,
        assigned_to_all_orgs: false,
        is_assigned: false,
        changed_at: Google::Protobuf::Timestamp.new(seconds: Time.current.to_i),
      }
    end

    publish(
      message,
      key: "#{business.customer.id}:#{business_team.id}",
      schema: "github.v1.BusinessTeamOrgAssignmentChanged",
    )
  end

  # Event: Business Team set to "assigned to all orgs"
  subscribe("business_team.assigned_to_all_organizations") do |payload|
    business_team_id = payload[:business_team_id]
    business_id = payload[:business_id]

    next unless business_team_id && business_id

    key, message = ActiveRecord::Base.connected_to(role: :reading) do
      business = Business.find(business_id)
      customer_id = T.must(business.customer).id

      key = "#{customer_id}:#{business_team_id}"
      msg = {
        request_context: serializer.request_context(GitHub.context.to_hash),
        business_id: business_id,
        business_team_id: business_team_id,
        org_id: 0,  # 0 indicates all orgs
        assigned_to_all_orgs: true,
        is_assigned: true,
        changed_at: Google::Protobuf::Timestamp.new(seconds: Time.current.to_i),
      }

      [key, msg]
    end

    publish(
      message,
      key: key,
      schema: "github.v1.BusinessTeamOrgAssignmentChanged",
    )
  end

  # Event: Business Team unset from "assigned to all orgs"
  subscribe("business_team.unassigned_from_all_organizations") do |payload|
    business_team_id = payload[:business_team_id]
    business_id = payload[:business_id]

    next unless business_team_id && business_id

    key, message = ActiveRecord::Base.connected_to(role: :reading) do
      business = Business.find(business_id)
      customer_id = T.must(business.customer).id

      key = "#{customer_id}:#{business_team_id}"
      msg = {
        request_context: serializer.request_context(GitHub.context.to_hash),
        business_id: business_id,
        business_team_id: business_team_id,
        org_id: 0,
        assigned_to_all_orgs: true,
        is_assigned: false,
        changed_at: Google::Protobuf::Timestamp.new(seconds: Time.current.to_i),
      }

      [key, msg]
    end

    publish(
      message,
      key: key,
      schema: "github.v1.BusinessTeamOrgAssignmentChanged",
    )
  end
end
