# typed: strict
# frozen_string_literal: true

module Platform
  module Inputs
    class RepositoryInvitationOrder < Platform::Inputs::Base
      description "Ordering options for repository invitation connections."

      argument :field, Enums::RepositoryInvitationOrderField, "The field to order repository invitations by.", required: true
      argument :direction, Enums::OrderDirection, "The ordering direction.", required: true
    end
  end
end
