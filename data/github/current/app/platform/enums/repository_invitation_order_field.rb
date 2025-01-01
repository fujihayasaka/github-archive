# typed: strict
# frozen_string_literal: true

module Platform
  module Enums
    class RepositoryInvitationOrderField < Platform::Enums::Base
      description "Properties by which repository invitation connections can be ordered."

      value "CREATED_AT", "Order repository invitations by creation time"
    end
  end
end
