# typed: true
# frozen_string_literal: true

class Orgs::Invitations::OptOutConfirmationView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :invitation, :invitation_token
  delegate :organization, to: :invitation
end
