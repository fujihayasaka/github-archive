# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    module AuditLog
      class OperationType < Platform::Enums::Base
        description "The corresponding operation type for the action"


        value "ACCESS", "An existing resource was accessed", value: Audit::OperationTypes::ACCESS
        value "AUTHENTICATION", "A resource performed an authentication event", value: Audit::OperationTypes::AUTHENTICATION
        value "CREATE", "A new resource was created", value: Audit::OperationTypes::CREATE
        value "MODIFY", "An existing resource was modified", value: Audit::OperationTypes::MODIFY
        value "REMOVE", "An existing resource was removed", value: Audit::OperationTypes::REMOVE
        value "RESTORE", "An existing resource was restored", value: Audit::OperationTypes::RESTORE
        value "TRANSFER", "An existing resource was transferred between multiple resources", value: Audit::OperationTypes::TRANSFER
      end
    end
  end
end
