# typed: true
# frozen_string_literal: true

module AuditLogEntry::EnterpriseDependency
  extend ActiveSupport::Concern

  class_methods do
    def business_action_names
      if GitHub.single_business_environment?
        business_server_action_names
      else
        business_cloud_action_names
      end
    end

    def business_cloud_action_names
      AuditLogEntry::Actions::BUSINESS_ACTION_NAMES
    end

    def business_server_action_names
      AuditLogEntry::Actions::BUSINESS_SERVER_ACTION_NAMES
    end

    def business_api_only_action_names
      AuditLogEntry::Actions::BUSINESS_API_ONLY_ACTION_NAMES
    end

    def enterprise_managed_user_action_names
      AuditLogEntry::Actions::BUSINESS_ACTION_NAMES + AuditLogEntry::Actions::USER_ACTION_NAMES
    end
  end
end
