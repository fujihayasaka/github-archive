# typed: strict
# frozen_string_literal: true

module CopilotSpaces
  module RoleMappingHelper
    # Maps role name strings to Role objects for Copilot Spaces
    sig { params(role_name: String).returns(T.nilable(Role)) }
    def self.requested_role_by_name(role_name)
      case role_name
      when "custom_copilot_reader"
        Role.custom_copilot_reader_role
      when "custom_copilot_writer"
        Role.custom_copilot_writer_role
      when "custom_copilot_admin"
        Role.custom_copilot_admin_role
      else
        nil
      end
    end

    # Maps role name strings to Role objects for Copilot Spaces, raising on invalid roles
    sig { params(role_name: String).returns(Role) }
    def self.requested_role_by_name!(role_name)
      requested_role_by_name(role_name) || raise("Unsupported Copilot Space role type: #{role_name}")
    end
  end
end
