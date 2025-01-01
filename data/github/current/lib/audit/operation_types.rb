# typed: true
# frozen_string_literal: true

module Audit
  module OperationTypes
    # Public: A new resource was created
    CREATE = "create"

    # Public: An existing resource was accessed
    ACCESS = "access"

    # Public: An existing resource was modified
    MODIFY = "modify"

    # Public: An existing resource was removed
    REMOVE = "remove"

    # Public: A resource performed an authentication event
    AUTHENTICATION = "authentication"

    # Public: An existing resource was transferred between multiple resources
    TRANSFER = "transfer"

    # Public: An existing resource was restored
    RESTORE = "restore"
  end
end
