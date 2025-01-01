# typed: true
# frozen_string_literal: true

class Orgs::People::PendingCollaboratorInvitationsListView < Orgs::OverviewView
  attr_reader :invitations,
              :invitees

  def initialize(**args)
    super(args)

    @invitations = args[:invitations]
    @invitees = args[:invitees]
  end

  def friendly_query(params)
    params[:query].blank? ? "" : " matching '#{h params[:query]}'"
  end
end
