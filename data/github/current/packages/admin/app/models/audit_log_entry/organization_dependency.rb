# typed: true
# frozen_string_literal: true

module AuditLogEntry::OrganizationDependency
  extend ActiveSupport::Concern

  class_methods do
    def organization_action_names
      AuditLogEntry::Actions::ORGANIZATION_ACTION_NAMES
    end

    def public_platform_organization_action_names
      AuditLogEntry::Actions::ORG_PUBLIC_PLATFORM_ACTION_NAMES
    end

    def organization_api_only_action_names
      AuditLogEntry::Actions::ORG_API_ONLY_ACTION_NAMES
    end

    def all_platform_organization_action_names
      @all_platform_organization_action_names ||= organization_action_names.select do |action|
        Platform::Schema.get_type("#{action.tr(".", "_").camelize}AuditEntry").present?
      end
    end
  end
end
