# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class EnterpriseMemberInvitationOrderField < Platform::Enums::Base
      description "Properties by which enterprise member invitation connections can be ordered."

      value "CREATED_AT", "Order enterprise member invitations by creation time", value: "created_at"
    end
  end
end
