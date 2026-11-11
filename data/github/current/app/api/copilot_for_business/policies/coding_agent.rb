# typed: strict
# frozen_string_literal: true

class Api::CopilotForBusiness::Policies::CodingAgent < Api::App
  put "/enterprises/:enterprise_id/copilot/policies/coding_agent", read_from_replicas: true, operation_id: "copilot/set-enterprise-coding-agent-policy" do
    data = receive_with_openapi
    business = find_enterprise!
    copilot_business = Copilot::Business.new(business)

    control_access :copilot_enterprise_seat_management_writer,
      resource: business,
      allow_user_via_granular_actor: false,
      allow_integrations: false,
      forbid: true,
      forbid_message: Copilot::ENTERPRISE_ADMIN_FORBID_MESSAGE

    policy_state = data.dig("policy_state")
    if copilot_business.is_standalone_business? && (policy_state == "enabled_for_selected_orgs" || policy_state == "configured_by_org_admins")
      deliver_error! 400, message: "Copilot Standalone enterprises do not support the '#{policy_state}' policy state because they do not have organizations."
    end
    # At product's request, the states passed into the API do not match the values used by the Policy system
    policy_states = {
      "configured_by_org_admins" => "no_policy",
      "enabled_for_selected_orgs" => Copilot::Policies::CodingAgent::ENTERPRISE_MANAGEMENT_VALUE,
      "enabled_for_all_orgs" => "enabled",
      "disabled_for_all_orgs" => "disabled"
    }
    with_write(clusters: [ApplicationRecord::Copilot]) do
      Copilot::Policies::CodingAgent.update_business(copilot_business, policy_states[policy_state])
    end

    deliver_empty status: 204
  end

  post "/enterprises/:enterprise_id/copilot/policies/coding_agent/organizations", read_from_replicas: true, operation_id: "copilot/add-organizations-to-enterprise-coding-agent-policy" do
    data = receive_with_openapi
    business = find_enterprise!
    copilot_business = Copilot::Business.new(business)
    control_access :copilot_enterprise_seat_management_writer,
      resource: business,
      allow_user_via_granular_actor: false,
      allow_integrations: false,
      forbid: true,
      forbid_message: Copilot::ENTERPRISE_ADMIN_FORBID_MESSAGE
    deliver_error! 400, message: "This enterprise's coding agent policy is not set to enabled_for_selected_orgs." unless copilot_business.swe_agent_no_policy? && copilot_business.coding_agent_enterprise_management_enabled?

    org_ids = get_org_ids_from_body(business, data)
    with_write(clusters: [ApplicationRecord::Copilot]) do
      Copilot::Policies::CodingAgent.bulk_update_org_policies(
        business: copilot_business,
        org_ids: org_ids,
        enable: true
      )
    end

    deliver_empty status: 204
  end

  delete "/enterprises/:enterprise_id/copilot/policies/coding_agent/organizations", read_from_replicas: true, operation_id: "copilot/remove-organizations-from-enterprise-coding-agent-policy" do
    data = receive_with_openapi
    business = find_enterprise!
    copilot_business = Copilot::Business.new(business)
    control_access :copilot_enterprise_seat_management_writer,
      resource: business,
      allow_user_via_granular_actor: false,
      allow_integrations: false,
      forbid: true,
      forbid_message: Copilot::ENTERPRISE_ADMIN_FORBID_MESSAGE
    deliver_error! 400, message: "This enterprise's coding agent policy is not set to enabled_for_selected_orgs." unless copilot_business.swe_agent_no_policy? && copilot_business.coding_agent_enterprise_management_enabled?

    org_ids = get_org_ids_from_body(business, data)
    with_write(clusters: [ApplicationRecord::Copilot]) do
      Copilot::Policies::CodingAgent.bulk_update_org_policies(
        business: copilot_business,
        org_ids: org_ids,
        enable: false
      )
    end

    deliver_empty status: 204
  end

  private

  sig do
    params(
      business: Business,
      data: T::Hash[T.untyped, T.untyped]
    ).returns(T::Array[Integer])
  end
  def get_org_ids_from_body(business, data)
    org_ids = T.let([], T::Array[Integer])

    # Find orgs with custom properties
    properties = data.fetch("custom_properties", [])
    properties.each do |property|
      property_name = property.dig("property_name")
      values = property.dig("values")

      org_ids |= Orgs.domain.custom_properties.organizations_with_property_values(
        business: business,
        property_name: property_name,
        values: values
      ).pluck(:id)
    end

    # Find orgs by login
    org_logins = data.fetch("organizations", [])
    org_ids |= business.organizations.where(display_login: org_logins).pluck(:id)

    Copilot::Business.new(business).copilot_enabled_organization_ids_among(org_ids)
  end
end
