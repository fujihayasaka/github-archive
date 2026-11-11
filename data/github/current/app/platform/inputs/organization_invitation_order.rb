# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class OrganizationInvitationOrder < Platform::Inputs::Base
      description "Ordering options for organization invitation connections"
      visibility :under_development

      argument :field, Enums::OrganizationInvitationOrderField, "The field to order organization invitations by.", required: true
      argument :direction, Enums::OrderDirection, "The ordering direction.", required: true
    end
  end
end
