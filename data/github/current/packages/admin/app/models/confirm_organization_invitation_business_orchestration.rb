# typed: true
# frozen_string_literal: true

class ConfirmOrganizationInvitationBusinessOrchestration < BusinessOrchestration
  step :record_invitee_billing_type do
    invitation = BusinessOrganizationInvitation.find(data[:invitation_id])
    invitee = T.must(invitation.invitee)
    with_write { invitation.update_attribute(:invitee_billing_type, invitee.billing_type) }
  end

  step :add_organization_to_business do
    invitation = BusinessOrganizationInvitation.find(data[:invitation_id])
    invitee = T.must(invitation.invitee)
    confirmer = T.must(actor)
    with_write { T.must(business).add_organization(invitee, actor: confirmer) }
  end

  step :transfer_marketplace_purchases do
    invitation = BusinessOrganizationInvitation.find(data[:invitation_id])
    invitee = T.must(invitation.invitee)
    confirmer = T.must(actor)
    with_write { T.must(business).transfer_marketplace_purchases_from_org_to_business(invitee, confirmer) }
  end

  step :update_invitee_billing_and_plan do
    invitation = BusinessOrganizationInvitation.find(data[:invitation_id])
    invitee = T.must(invitation.invitee)
    with_write do
      if T.must(business).trial?
        invitee.suspend_billing
      else
        invitee.plan = "business_plus"
      end
      invitee.expire_active_coupon
      invitee.save
    end
  end

  # Cancel sibling pending invitations to other businesses. The org's
  # implicit refusal of those is recorded as performed by an admin of the
  # invitee org
  step :cancel_implicitly_refused_invitations do
    invitation = BusinessOrganizationInvitation.find(data[:invitation_id])
    invitee = T.must(invitation.invitee)
    org_admin = invitee.admins.first
    if org_admin.nil?
      GitHub.logger.warn(
        "Skipping cancel_implicitly_refused_invitations from ConfirmOrganizationInvitationBusinessOrchestration: org has no admins",
        "gh.business_organization_invitation.id" => invitation.id,
        "gh.organization.id" => invitee.id,
      )
      return
    end

    invitee.business_invitations.pending.where.not(business: T.must(business)).each do |inv|
      with_write { inv.cancel(org_admin) }
    end
  end

  # Stamping `confirmed_at` is what flips the invitation
  # status to `:confirmed`, so this step runs last to avoid exposing
  # partial-success states.
  step :mark_confirmed do
    invitation = BusinessOrganizationInvitation.find(data[:invitation_id])
    with_write do
      invitation.touch(:confirmed_at)
      invitation.touch(:completed_at) if data[:completed]
    end
  end

  job_start

  # Depends on `invitee.business` being set
  # (which `add_organization_to_business` did synchronously).
  step :enqueue_post_confirmation_work do
    confirmer = T.must(actor)
    invitation = BusinessOrganizationInvitation.find(data[:invitation_id])
    invitee = T.must(invitation.invitee)

    Billing::EnterpriseCloudTrialCheckJob.perform_later(invitee.id)
    invitee.instrument(
      :confirm_business_invitation,
      { business: T.must(business), actor: confirmer, invitation_id: invitation.id },
    )
  end
end
