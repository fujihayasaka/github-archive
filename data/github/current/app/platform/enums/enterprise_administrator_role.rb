# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class EnterpriseAdministratorRole < Platform::Enums::Base
      description "The possible administrator roles in an enterprise account."

      value "OWNER", "Represents an owner of the enterprise account.", value: "owner"
      value "BILLING_MANAGER", "Represents a billing manager of the enterprise account.", value: "billing_manager"
    end
  end
end
