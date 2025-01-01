# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class EnterpriseAdministratorRole < Platform::Enums::Base
      description "The possible administrator roles in an enterprise account."

      value "OWNER", "Represents an owner of the enterprise account.", value: "owner"
      value "BILLING_MANAGER", "Represents a billing manager of the enterprise account.", value: "billing_manager"
      value "UNAFFILIATED", "Unaffiliated member of the enterprise account without an admin role.", value: "unaffiliated_member"
    end
  end
end
