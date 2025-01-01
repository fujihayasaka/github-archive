# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class EnterpriseMembershipType < Platform::Enums::Base

      # Represents the possible filters passed to User#enterprises
      #
      #   - :all
      #   - :admin
      #   - :billing_manager
      #   - :org_membership

      description "The possible values we have for filtering Platform::Objects::User#enterprises."

      value "ALL", "Returns all enterprises in which the user is a member, admin, or billing manager.", value: :all
      value "ADMIN", "Returns all enterprises in which the user is an admin.", value: :admin
      value "BILLING_MANAGER", "Returns all enterprises in which the user is a billing manager.", value: :billing_manager
      value "ORG_MEMBERSHIP", "Returns all enterprises in which the user is a member of an org that is owned by the enterprise.", value: :org_membership
    end
  end
end
