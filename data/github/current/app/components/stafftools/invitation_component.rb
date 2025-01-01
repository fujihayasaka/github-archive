# typed: true
# frozen_string_literal: true

class Stafftools::InvitationComponent < ApplicationComponent
  attr_reader :invitation, :failed

  def initialize(invitation:, failed: false)
    @invitation = invitation
    @failed = failed
  end

  private

  def user
    invitation.invitee
  end

  def inviter
    invitation.inviter
  end

  def repo_invitation?
    invitation.is_a?(::RepositoryInvitation)
  end

  def failed?
    failed
  end

  def audit_log_query
    return if repo_invitation?

    email_or_id_phrase = if invitation.invitee_id
      if helpers.driftwood_ade_query?(current_user)
        "| where user_id == #{invitation.invitee_id}"
      else
        "user_id:#{invitation.invitee_id}"
      end
    elsif invitation.email
      if helpers.driftwood_ade_query?(current_user)
        "| where data.email == '#{invitation.email}'"
      else
        "data.email:#{invitation.email}"
      end
    end

    if helpers.driftwood_ade_query?(current_user)
      <<~KQL
        webevents
        | where action == 'org.invite_member'
        | where actor_id == #{invitation.inviter_id}
        | where org_id == #{invitation.organization_id}
        #{email_or_id_phrase}
      KQL
    else
      "action:org.invite_member actor_id:#{invitation.inviter_id} org_id:#{invitation.organization_id} #{email_or_id_phrase}"
    end
  end
end
