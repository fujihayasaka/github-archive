# typed: true
# frozen_string_literal: true

# REST API endpoints for Enterprise MCP Registry settings
#
# These endpoints allow enterprise administrators to configure MCP (Model Context Protocol)
# registry settings programmatically, providing the same functionality available in the
# Enterprise UI at /enterprises/:slug/ai_controls/mcp
#
# Endpoints:
#   GET  /enterprises/:enterprise_id/ai-controls/mcp - Get MCP registry settings
#   PATCH /enterprises/:enterprise_id/ai-controls/mcp - Update MCP registry settings
#
# Permissions:
#   - read_enterprise_ai_controls (for GET)
#   - write_enterprise_ai_controls (for PATCH)
#
# Token Scopes:
#   - read:enterprise (for GET)
#   - admin:enterprise (for PATCH)
#
# @see packages/copilot/app/models/copilot/mcp_registry.rb

class Api::CopilotForBusiness::McpRegistry < Api::App
  include FeatureFlagHelper
  include ReceiveSchemaWithOpenApi

  FEATURE_NOT_AVAILABLE_MESSAGE = "MCP registry is not available for this enterprise."
  DOCUMENTATION_URL = "#{GitHub::Config::DOCS_BASE_URL}/rest/enterprise-admin/ai-controls"

  # GET /enterprises/:enterprise_id/ai-controls/mcp
  #
  # Retrieves the current MCP registry settings for an enterprise.
  #
  # @param enterprise_id [String] The slug or ID of the enterprise
  #
  # @response 200 [Object] Current MCP registry settings
  # @response 403 [Object] Forbidden - Insufficient permissions
  # @response 404 [Object] Not Found - Enterprise not found or feature not available
  #
  get "/enterprises/:enterprise_id/ai-controls/mcp",
      operation_id: "enterprise-admin/get-mcp-registry-settings" do

    enterprise = find_enterprise!

    ensure_mcp_feature_available!(enterprise)

    control_access :standard_authorization,
      resource: enterprise,
      permission: :read_enterprise_ai_controls,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: Copilot::ENTERPRISE_ADMIN_INSUFFICIENT_PERMISSIONS_MESSAGE

    receive_with_openapi

    mcp_settings = get_enterprise_mcp_settings(enterprise)
    deliver_raw(mcp_settings)
  end

  # PATCH /enterprises/:enterprise_id/ai-controls/mcp
  #
  # Updates the MCP registry settings for an enterprise.
  #
  # @param enterprise_id [String] The slug or ID of the enterprise
  #
  # @body policy [String] The MCP policy ("enabled", "disabled")
  # @body registry_access [String] Registry access mode ("allow_all", "registry_only")
  # @body registry_url [String, nil] The allowed MCP registry URL (optional, used when registry_access is "registry_only")
  #
  # @response 200 [Object] Updated MCP registry settings
  # @response 400 [Object] Bad Request - Invalid parameters
  # @response 403 [Object] Forbidden - Insufficient permissions
  # @response 404 [Object] Not Found - Enterprise not found or feature not available
  # @response 422 [Object] Unprocessable Entity - Validation failed
  #
  patch "/enterprises/:enterprise_id/ai-controls/mcp", read_from_replicas: true,
        operation_id: "enterprise-admin/update-mcp-registry-settings" do

    enterprise = find_enterprise!

    ensure_mcp_feature_available!(enterprise)

    control_access :standard_authorization,
      resource: enterprise,
      permission: :write_enterprise_ai_controls,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: Copilot::ENTERPRISE_ADMIN_INSUFFICIENT_PERMISSIONS_MESSAGE

    data = receive_with_openapi

    # Validate and update MCP settings
    result = update_enterprise_mcp_settings(enterprise, data, current_user)

    if result[:success]
      # Create audit log entry
      create_mcp_audit_log(enterprise, result[:old_settings], result[:new_settings])

      deliver_raw(result[:settings], status: 200)
    else
      deliver_error!(
        result[:status] || 422,
        message: result[:message] || "Validation failed",
        errors: result[:errors],
        documentation_url: DOCUMENTATION_URL
      )
    end
  end

  private

  # Ensure MCP feature is available for the enterprise
  #
  # @param enterprise [Business] The enterprise
  # @raise [404] If feature is not available
  def ensure_mcp_feature_available!(enterprise)
    # Check if enterprise has Copilot enabled
    copilot_business = Copilot::Business.new(enterprise)
    unless copilot_business.copilot_enabled?
      deliver_error!(404,
        message: FEATURE_NOT_AVAILABLE_MESSAGE,
        documentation_url: DOCUMENTATION_URL
      )
    end

    # Check if MCP registry feature is enabled
    unless enterprise.feature_flag_enabled?(:copilot_mcp_registry_api, default: false)
      deliver_error!(404,
        message: FEATURE_NOT_AVAILABLE_MESSAGE,
        documentation_url: DOCUMENTATION_URL
      )
    end
  end

  # Get current MCP settings for an enterprise
  #
  # @param enterprise [Business] The enterprise
  # @return [Hash] The MCP settings
  def get_enterprise_mcp_settings(enterprise)
    copilot_business = Copilot::Business.new(enterprise)
    mcp_registry = Copilot::McpRegistry.for_business(enterprise).first

    policy = if copilot_business.mcp_disabled?
      "disabled"
    elsif copilot_business.mcp_enabled?
      "enabled"
    elsif copilot_business.mcp_no_policy?
      "organizations_decide"
    else
      "unconfigured"
    end

    if mcp_registry.nil?
      return {
        enabled: policy == "enabled",
        policy: policy,
        registry_access: nil,
        registry_url: nil,
        created_at: nil,
        updated_at: nil,
        updated_by: nil
      }
    end

    {
      enabled: policy == "enabled",
      policy: policy,
      registry_access: mcp_registry.registry_access,
      registry_url: mcp_registry.registry_url,
      created_at: mcp_registry.created_at&.iso8601,
      updated_at: mcp_registry.updated_at&.iso8601,
      updated_by: format_user(mcp_registry.updated_by)
    }
  end

  # Update MCP settings for an enterprise
  #
  # @param enterprise [Business] The enterprise
  # @param data [Hash] The new settings
  # @param user [User] The user making the change
  # @return [Hash] Result with :success, :settings, :errors
  def update_enterprise_mcp_settings(enterprise, data, user)
    old_settings = get_enterprise_mcp_settings(enterprise)
    copilot_business = Copilot::Business.new(enterprise)

    # Validate input
    validation_errors = validate_mcp_input(data)
    if validation_errors.any?
      return {
        success: false,
        status: 400,
        message: "Invalid request",
        errors: validation_errors
      }
    end

    mcp_registry = Copilot::McpRegistry.for_business(enterprise).first_or_initialize

    # Store policy for later update (after all validations pass)
    policy_to_apply = nil

    # Validate policy if provided
    if data.key?("policy") || data.key?(:policy)
      policy = data["policy"] || data[:policy]
      unless %w[enabled disabled organizations_decide].include?(policy)
        return {
          success: false,
          status: 422,
          message: "Invalid policy value",
          errors: [{ field: "policy", code: "invalid", message: "Policy must be 'enabled', 'disabled', or 'organizations_decide'" }]
        }
      end
      policy_to_apply = policy
    end

    # Determine effective policy (from request or current state)
    effective_policy = policy_to_apply || old_settings[:policy]

    # Registry settings can only be modified when policy is 'enabled'
    registry_settings_provided = (data.key?("registry_access") || data.key?(:registry_access) ||
                                   data.key?("registry_url") || data.key?(:registry_url))
    if registry_settings_provided && effective_policy != "enabled"
      return {
        success: false,
        status: 400,
        message: "Registry settings can only be configured when policy is 'enabled'",
        errors: [{ field: "registry_access", code: "invalid", message: "Set policy to 'enabled' before configuring registry settings" }]
      }
    end

    # Update registry access if provided
    if data.key?("registry_access") || data.key?(:registry_access)
      registry_access = data["registry_access"] || data[:registry_access]
      unless %w[allow_all registry_only].include?(registry_access)
        return {
          success: false,
          status: 422,
          message: "Invalid registry_access value",
          errors: [{ field: "registry_access", code: "invalid", message: "Registry access must be 'allow_all' or 'registry_only'" }]
        }
      end
      mcp_registry.registry_access = registry_access
    end

    # Update registry URL if provided
    if data.key?("registry_url") || data.key?(:registry_url)
      registry_url = data["registry_url"] || data[:registry_url]

      # Determine the effective registry_access value (from request or model)
      effective_registry_access = if data.key?("registry_access") || data.key?(:registry_access)
        data["registry_access"] || data[:registry_access]
      else
        mcp_registry.registry_access
      end

      # Validate URL if registry_access is registry_only
      if effective_registry_access == "registry_only" && registry_url.blank?
        return {
          success: false,
          status: 400,
          message: "Registry URL is required when registry_access is 'registry_only'",
          errors: [{ field: "registry_url", code: "required", message: "Registry URL cannot be blank when using registry_only access" }]
        }
      end

      if registry_url.present? && !valid_registry_url?(registry_url)
        return {
          success: false,
          status: 400,
          message: "Invalid registry URL",
          errors: [{ field: "registry_url", code: "invalid", message: "Registry URL must be a valid HTTPS URL" }]
        }
      end

      mcp_registry.registry_url = registry_url
    end

    # Set entity and updated_by
    mcp_registry.entity = enterprise
    mcp_registry.entity_type = "Business"
    mcp_registry.updated_by = user

    # Validate the model
    unless mcp_registry.valid?
      return {
        success: false,
        status: 422,
        message: "Validation failed",
        errors: mcp_registry.errors.full_messages.map { |msg| { message: msg } }
      }
    end

    # Save within write cluster
    begin
      with_write(clusters: [ApplicationRecord::Copilot]) do
        # Apply policy change inside the write block, after all validations
        if policy_to_apply
          case policy_to_apply
          when "enabled"
            copilot_business.mcp_enabled!
          when "disabled"
            copilot_business.mcp_disabled!
          when "organizations_decide"
            copilot_business.mcp_no_policy!
          end
        end
        mcp_registry.save!
      end
    rescue ActiveRecord::RecordInvalid => e
      return {
        success: false,
        status: 422,
        message: "Failed to save settings",
        errors: [{ message: e.message }]
      }
    end

    new_settings = get_enterprise_mcp_settings(enterprise)

    {
      success: true,
      settings: new_settings,
      old_settings: old_settings,
      new_settings: new_settings
    }
  end

  # Validate MCP input data
  #
  # @param data [Hash] The input data
  # @return [Array<Hash>] Array of error objects
  def validate_mcp_input(data)
    errors = []

    # Check for unknown keys
    allowed_keys = %w[policy registry_access registry_url]
    unknown_keys = data.keys.map(&:to_s) - allowed_keys

    if unknown_keys.any?
      errors << {
        field: unknown_keys.first,
        code: "unknown",
        message: "Unknown field: #{unknown_keys.first}"
      }
    end

    errors
  end

  # Validate registry URL format
  #
  # @param url [String] The URL to validate
  # @return [Boolean] True if valid
  def valid_registry_url?(url)
    return false if url.blank?

    uri = URI.parse(url)
    uri.is_a?(URI::HTTPS) && uri.host.present?
  rescue URI::InvalidURIError
    false
  end

  # Format user for API response
  #
  # @param user [User, nil] The user
  # @return [Hash, nil] User object or nil
  def format_user(user)
    return nil if user.nil?

    {
      login: user.display_login,
      id: user.id,
      type: user.type,
      avatar_url: user.primary_avatar_url
    }
  end

  # Create audit log entry for MCP changes
  #
  # @param enterprise [Business] The enterprise
  # @param old_settings [Hash] Previous settings
  # @param new_settings [Hash] New settings
  def create_mcp_audit_log(enterprise, old_settings, new_settings)
    return if old_settings == new_settings

    GitHub.instrument "enterprise.mcp_registry_updated", {
      actor: current_user,
      business: enterprise,
      old_value: old_settings.to_json,
      new_value: new_settings.to_json
    }
  end
end
