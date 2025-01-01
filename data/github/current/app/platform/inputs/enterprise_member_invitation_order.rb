# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class EnterpriseMemberInvitationOrder < Platform::Inputs::Base
      description "Ordering options for enterprise administrator invitation connections"

      argument :field, Enums::EnterpriseMemberInvitationOrderField, "The field to order enterprise member invitations by.", required: true
      argument :direction, Enums::OrderDirection, "The ordering direction.", required: true
    end
  end
end
