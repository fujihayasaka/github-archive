# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class OrganizationInvitationSource < Platform::Enums::Base
      docs_category :orgs
      description "The possible organization invitation sources."

      value "UNKNOWN", "The invitation was sent before this feature was added", value: "unknown"
      value "MEMBER", "The invitation was created from the web interface or from API", value: "member"
      value "SCIM", "The invitation was created from SCIM", value: "scim"
      value "ENTERPRISE_ORGANIZATION_CREATION", "The invitation was created with an enterprise organization", value: "enterprise_organization_creation"
    end
  end
end
