# typed: true
# frozen_string_literal: true

class Businesses::People::PendingInvitationsDialogViewComponent < ApplicationComponent
  include AvatarHelper

  def initialize(selected_invitations:, this_business:, redirect_to_path:, opts: { invitation_type: "member" })
    @selected_invitations = selected_invitations
    @this_business = this_business
    @redirect_to_path = redirect_to_path
    @opts = opts
  end

  def selected_invitation_ids
    @selected_invitations.map(&:id)
  end

  def cancel_path
    case invitation_type
    when "admin"
      enterprise_cancelable_pending_admins_path(@this_business)
    when "collaborator"
      enterprise_cancelable_pending_collaborators_path(@this_business)
    when "unaffiliated"
      enterprise_cancelable_pending_unaffiliated_members_path(@this_business)
    else
      enterprise_cancelable_pending_members_path(@this_business)
    end
  end

  def invitation_type
    if defined? @opts[:invitation_type]
      @opts[:invitation_type]
    else
      "member"
    end
  end
end
