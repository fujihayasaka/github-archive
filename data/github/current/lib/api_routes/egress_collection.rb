# typed: true
# frozen_string_literal: true

# EgressCollection munges egress roles and access definitions to decorate routes.
class ApiRoutes::EgressCollection

  attr_reader :access_definitions, :roles
  def initialize(access_definitions:, roles:)
    @access_definitions = access_definitions
    @roles = roles
  end

  def process(collection)
    collection.endpoints.each do |endpoint|
      roles = endpoint.control_access_calls.map do |control_access_call|
        Array(access_definition_to_roles[control_access_call.verb]).select { |role| role_to_permissions[role] }
      end.flatten
      permissions = T.let({}, T::Hash[String, Symbol])
      roles.each do |role|
        permissions = permissions.merge role_to_permissions[role]
      end
      endpoint.permissions = permissions
    end

    collection
  end

  private

  def role_to_permissions
    @role_map ||= roles.each_with_object({}) do |role, map|
      map[role.name] = role.permissions
    end
  end

  def access_definition_to_roles
    @access_definition_map ||= access_definitions.each_with_object({}) do |access_definition, map|
      map[access_definition.verb] = access_definition.roles
    end
  end
end
