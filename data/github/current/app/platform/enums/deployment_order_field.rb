# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class DeploymentOrderField < Platform::Enums::Base
      description "Properties by which deployment connections can be ordered."

      value "CREATED_AT", "Order collection by creation time", value: "created_at"
    end
  end
end
