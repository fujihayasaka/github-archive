# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class OrganizationInvitationOrderField < Platform::Enums::Base
      description "Properties by which organization invitation connections can be ordered."
      visibility :under_development

      value "CREATED_AT", "Order organization invitations by creation time", value: "created_at"
    end
  end
end
