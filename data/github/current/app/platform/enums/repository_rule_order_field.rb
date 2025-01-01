# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class RepositoryRuleOrderField < Platform::Enums::Base
      description "Properties by which repository rule connections can be ordered."

      value "UPDATED_AT", "Order repository rules by updated time", value: "updated_at"
      value "CREATED_AT", "Order repository rules by created time", value: "created_at"
      value "TYPE", "Order repository rules by type", value: "rule_type"
    end
  end
end
