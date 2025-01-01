# typed: true
# frozen_string_literal: true

class Businesses::People::PendingInvitationToolbarActionsComponent < ApplicationComponent
  def initialize(business:, selected_invitations:, pending_invitations:, opts: { invitation_type: "member" })
    @business = business
    @selected_invitations = selected_invitations
    @pending_invitations = pending_invitations
    @opts = opts
  end

  def redirect_path
    enterprise_pending_members_path(@business)
  end

  def bulk_delete_dialog_path
    enterprise_cancel_pending_invitations_dialog_path \
      @business,
      invitation_type: @opts[:invitation_type],
      invitation_ids: @selected_invitations.map(&:id)
  end

  def all_invitations_selected?
    params[:invitation_ids]&.include?("all")
  end
end
