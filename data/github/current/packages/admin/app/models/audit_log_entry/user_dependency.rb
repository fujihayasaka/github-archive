# typed: true
# frozen_string_literal: true

module AuditLogEntry::UserDependency
  extend ActiveSupport::Concern

  class_methods do
    def user_action_names
      AuditLogEntry::Actions::USER_ACTION_NAMES
    end

    def user_dormancy_action_names
      AuditLogEntry::Actions::USER_DORMANCY_ACTION_NAMES
    end
  end
end
