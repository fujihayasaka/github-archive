# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class AuditLogOrderField < Platform::Enums::Base

      description "Properties by which Audit Log connections can be ordered."

      value "CREATED_AT", "Order audit log entries by timestamp", value: "timestamp"
    end
  end
end
