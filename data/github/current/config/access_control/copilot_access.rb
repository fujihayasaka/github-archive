# typed: strict
# frozen_string_literal: true

class Api::AccessControl < Egress::AccessControl
  define_access :generate_copilot_token do |access|
    access.ensure_context :resource
    access.allow :copilot_user
  end

  define_access :copilot_notification do |access|
    access.ensure_context :resource
    access.allow :copilot_user
  end

  define_access :copilot_repository_check do |access|
    access.ensure_context :resource
    access.allow :copilot_user
  end

  define_access :copilot_user_status do |access|
    access.ensure_context :resource
    access.allow :copilot_user_status_viewer
  end

  define_access :copilot_org_seat_management_writer do |access|
    access.ensure_context :resource
    access.allow :copilot_org_seat_management_writer
  end

  define_access :copilot_org_seat_management_reader do |access|
    access.ensure_context :resource
    access.allow :copilot_org_seat_management_reader
  end

  define_access :copilot_coding_agent_org_settings_writer do |access|
    access.ensure_context :resource
    access.allow :copilot_coding_agent_org_settings_writer
  end

  define_access :copilot_coding_agent_org_settings_reader do |access|
    access.ensure_context :resource
    access.allow :copilot_coding_agent_org_settings_reader
  end

  define_access :copilot_cloud_agent_repo_settings_reader do |access|
    access.ensure_context :resource
    access.allow :copilot_cloud_agent_repo_settings_reader
  end

  define_access :copilot_enterprise_seat_management_reader do |access|
    access.ensure_context :resource
    access.allow :copilot_enterprise_admin_reader
  end

  define_access :copilot_enterprise_seat_management_writer do |access|
    access.ensure_context :resource
    access.allow :copilot_enterprise_admin_writer
  end

  define_access :copilot_org_usage_metrics do |access|
    access.ensure_context :resource
    access.allow :copilot_org_usage_metrics_reader
  end

  define_access :copilot_enterprise_usage_metrics do |access|
    access.ensure_context :resource
    access.allow :copilot_enterprise_admin_reader
  end

  define_access :enterprise_copilot_metrics do |access|
    access.ensure_context :resource
    access.allow :enterprise_copilot_metrics_reader
  end

  define_access :organization_copilot_metrics do |access|
    access.ensure_context :resource
    access.allow :organization_copilot_metrics_reader
  end

  define_access :copilot_subscribe_limited_user_access do |access|
    access.ensure_context :resource
    access.allow :copilot_subscribe_limited_user
  end

  define_access :copilot_content_exclusion do |access|
    access.ensure_context :resource
    access.allow :copilot_content_exclusion_reader
  end

  define_access :copilot_org_custom_instructions do |access|
    access.ensure_context :user, :resource
    access.allow :copilot_user
  end

  define_access :copilot_code_review_feedback_writer do |access|
    access.ensure_context :resource
    access.allow :copilot_code_review_feedback_writer
  end

  define_access :copilot_workbench do |access|
    access.ensure_context :user, :resource
    access.allow :authenticated_user
  end

  define_access :write_copilot_chat_attachments do |access|
    access.ensure_context :user, :owner
    access.allow :copilot_chat_attachment_writer
  end

  define_access :copilot_mcp_registry do |access|
    access.ensure_context :resource
    access.allow :copilot_mcp_registry_reader
    access.allow :copilot_user
  end
end
