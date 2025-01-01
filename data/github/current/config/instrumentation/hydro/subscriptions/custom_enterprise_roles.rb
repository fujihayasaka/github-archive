# typed: true
# frozen_string_literal: true

# Hydro event subscriptions for custom enterprise roles.
Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("custom_enterprise_roles.role_created") do |payload|
    message = {
      role: serializer.custom_enterprise_role(payload[:role]),
      enterprise_custom_roles_count: payload[:enterprise_custom_roles_count]
    }

    publish(message, schema: "github.custom_enterprise_roles.v0.CustomEnterpriseRoleCreated")
  end

  subscribe("custom_enterprise_roles.role_deleted") do |payload|
    message = {
      role: serializer.custom_enterprise_role(payload[:role]),
      enterprise_custom_roles_count: payload[:enterprise_custom_roles_count]
    }

    publish(message, schema: "github.custom_enterprise_roles.v0.CustomEnterpriseRoleDeleted")
  end

  subscribe("custom_enterprise_roles.role_updated") do |payload|
    message = {
      role: serializer.custom_enterprise_role(payload[:role])
    }

    publish(message, schema: "github.custom_enterprise_roles.v0.CustomEnterpriseRoleUpdated")
  end
end
