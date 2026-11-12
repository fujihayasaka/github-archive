# frozen_string_literal: true

class StructuredAdvisoryPayloadReference < ApplicationRecord
  self.table_name = "advisory_payload_references"

  belongs_to :payload, class_name: "StructuredAdvisoryPayload", foreign_key: "advisory_payload_id", inverse_of: "vulnerabilities"

  before_destroy do
    versions.destroy_all
  end
end
