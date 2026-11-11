# typed: true
# frozen_string_literal: true

module CopilotSpaces
  module RoleMapping
    extend ActiveSupport::Concern

    # Convert API base_role name to internal enum value
    # @param api_role_name [String] The role name from API request (reader/writer/admin/no_access)
    # @return [Symbol, nil] The internal enum symbol (:custom_copilot_reader, :custom_copilot_writer, :custom_copilot_admin, :none) or nil if invalid
    def self.api_base_role_to_internal(api_role_name)
      return nil if api_role_name.nil?

      case api_role_name
      when "reader"
        :custom_copilot_reader
      when "writer"
        :custom_copilot_writer
      when "admin"
        :custom_copilot_admin
      when "no_access"
        :none
      else
        nil # Invalid role name
      end
    end

    # Convert internal base_role enum to API name
    # @param internal_role [String, Symbol] The internal enum value
    # @return [String] The API role name (reader/writer/admin/no_access)
    def self.internal_base_role_to_api(internal_role)
      case internal_role.to_s
      when "custom_copilot_reader"
        "reader"
      when "custom_copilot_writer"
        "writer"
      when "custom_copilot_admin"
        "admin"
      when "none"
        "no_access"
      else
        "no_access" # Default fallback
      end
    end

    module ClassMethods
      # Convert API base_role name to internal enum value
      # @param api_role_name [String] The role name from API request (reader/writer/admin/no_access)
      # @return [Symbol, nil] The internal enum symbol (:custom_copilot_reader, :custom_copilot_writer, :custom_copilot_admin, :none) or nil if invalid
      def api_base_role_to_internal(api_role_name)
        CopilotSpaces::RoleMapping.api_base_role_to_internal(api_role_name)
      end

      # Convert internal base_role enum to API name
      # @param internal_role [String, Symbol] The internal enum value
      # @return [String] The API role name (reader/writer/admin/no_access)
      def internal_base_role_to_api(internal_role)
        CopilotSpaces::RoleMapping.internal_base_role_to_api(internal_role)
      end
    end

    # Instance method versions for convenience
    # Convert API base_role name to internal enum value
    # @param api_role_name [String] The role name from API request (reader/writer/admin/no_access)
    # @return [Symbol, nil] The internal enum symbol (:custom_copilot_reader, :custom_copilot_writer, :custom_copilot_admin, :none) or nil if invalid
    def api_base_role_to_internal(api_role_name)
      CopilotSpaces::RoleMapping.api_base_role_to_internal(api_role_name)
    end

    # Convert internal base_role enum to API name
    # @param internal_role [String, Symbol] The internal enum value
    # @return [String] The API role name (reader/writer/admin/no_access)
    def internal_base_role_to_api(internal_role)
      CopilotSpaces::RoleMapping.internal_base_role_to_api(internal_role)
    end
  end
end
