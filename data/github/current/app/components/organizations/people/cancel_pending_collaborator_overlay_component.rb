# typed: true
# frozen_string_literal: true

# A component to manage how we display the overlay to cancel Pending
# Colalborator Invitations.
class Organizations::People::CancelPendingCollaboratorOverlayComponent < ApplicationComponent
  include AvatarHelper

  attr_reader :organization,
              :invitations,
              :invitees

  def initialize(organization:, invitations:, invitees:)
    @organization = organization
    @invitations = invitations
    @invitees = invitees
  end
end
