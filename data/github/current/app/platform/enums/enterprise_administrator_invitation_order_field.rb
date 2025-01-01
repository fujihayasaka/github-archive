# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class EnterpriseAdministratorInvitationOrderField < Platform::Enums::Base
      description "Properties by which enterprise administrator invitation connections can be ordered."

      value "CREATED_AT", "Order enterprise administrator member invitations by creation time", value: "created_at"
    end
  end
end
