# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class EnterpriseOrganizationInvitationOrderField < Platform::Enums::Base
      visibility :under_development
      description "Properties by which enterprise organization invitation connections can be ordered."

      value "CREATED_AT", "Order enterprise organization invitations by creation time", value: "created_at"
    end
  end
end
