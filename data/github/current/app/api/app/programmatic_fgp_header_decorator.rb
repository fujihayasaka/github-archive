# typed: true
# frozen_string_literal: true

module Api::App::ProgrammaticFgpHeaderDecorator
  ALLOWS_PERMISSIONLESS_ACCESS_STRING = "allows_permissionless_access=true"

  def self.build_header_string_for_permissions(permission_sets)
    permission_sets.map do |permissions|
      permissions.map do |resource, level|
        "#{resource}=#{level}"
      end.join(",")
    end.join("; ").freeze
  end

  def self.build_permission_set_map
    Apps::ProgrammaticAccessDefinitions.load_yaml.each_with_object({}) do |definition, hash|
      definition["operation_ids"].split(",").each do |operation_id|
        if definition["allows_permissionless_access"]
          hash[operation_id] = ALLOWS_PERMISSIONLESS_ACCESS_STRING
        elsif definition["permission_sets"].is_a?(Array) && permission_sets_include_todos?(definition["permission_sets"])
          next # Skip TODOs
        elsif definition["permission_sets"].is_a?(Array)
          hash[operation_id] = build_header_string_for_permissions(definition["permission_sets"])
        end
      end
    end
  end

  def self.permission_sets_include_todos?(permission_sets)
    permission_sets.any? { |permission_set| permission_set.is_a?(String) && permission_set.start_with?("TODO:") }
  end


  OPERATION_ID_PERMISSION_SET_MAP = build_permission_set_map

  def permissions_header_for_request
    return :unsupported unless @operation
    return :unsupported unless OPERATION_ID_PERMISSION_SET_MAP.key?(@operation.id)

    permissions = OPERATION_ID_PERMISSION_SET_MAP[@operation.id]

    return permissions if permissions

    :unsupported
  end
end
