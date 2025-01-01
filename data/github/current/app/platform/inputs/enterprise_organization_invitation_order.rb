# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class EnterpriseOrganizationInvitationOrder < Platform::Inputs::Base
      visibility :under_development
      description "Ordering options for enterprise organization invitation connections"

      argument :field, Enums::EnterpriseOrganizationInvitationOrderField, "The field to order enterprise organization invitations by.", required: true
      argument :direction, Enums::OrderDirection, "The ordering direction.", required: true
    end
  end
end
