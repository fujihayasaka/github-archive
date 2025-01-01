# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class EnterpriseUserAccountMembershipRole < Platform::Enums::Base
      description "The possible roles for enterprise membership."

      value "MEMBER", "The user is a member of an organization in the enterprise.", value: "member"
      value "OWNER", "The user is an owner of an organization in the enterprise.", value: "owner"
      value "ENTERPRISE_OWNER", "The user is an owner of the enterprise.", value: "enterprise_owner" do
        visibility :internal,
        environments: [:dotcom]
      end
      value "BILLING_MANAGER", "The user is a billing manager for the enterprise.", value: "billing_manager" do
        visibility :internal,
        environments: [:dotcom]
      end
      value "GUEST_COLLABORATOR", "The user is a guest collaborator in the enterprise.", value: "guest_collaborator" do
        visibility :internal,
        environments: [:dotcom]
      end
      value "UNAFFILIATED", "The user is not an owner of the enterprise, and not a member or owner of any organizations in the enterprise; only for EMU-enabled enterprises.", value: "unaffiliated" do
        visibility :public,
        environments: [:dotcom]
      end
    end
  end
end
