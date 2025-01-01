# typed: false
# frozen_string_literal: true

module InvitationsAnalyticsHelper
  def invite_hydro_click_tracking_attributes(organization:, actor:, event_type:, invitee: nil)
    hydro_click_tracking_attributes("organization.invite.click", {
      user_id: current_user&.id,
      organization_id: organization&.id,
      event_type: event_type,
      invitee: invitee,
    })
  end

  def invite_skip_hydro_tracking
    invite_hydro_click_tracking_attributes(
      organization: current_organization,
      actor: current_user,
      event_type: :SKIP
    )
  end
end
