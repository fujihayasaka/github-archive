# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class BusinessTrialCancellationCleanupJob < ApplicationJob
  queue_as :business_trial_cancellation_cleanup

  retry_on_dirty_exit

  DELETE_BATCH_SIZE = 1000

  resolve_tenant_context do |business|
    business
  end

  # Public - job to trigger cleanup after the business trial was cancelled
  def perform(business)
    invited_organization_ids = business.organization_invitations.with_status(:confirmed).distinct.pluck(:invitee_id)
    invited_organization_ids.each_slice(DELETE_BATCH_SIZE) do |organization_ids|
      Organization.where(id: organization_ids).find_each do |organization|
        with_write do
          T.must(business).remove_organization(organization) if business == organization.business
        end
      end
    end

    business.reload
    with_write do
      if business.upgraded_from.present? && business.upgraded_from.business_membership.present? && business.upgraded_from.business_membership.business_id == business.id
        business.remove_organization(business.upgraded_from)
      end
      business.organization_invitations.where(confirmed_at: nil).destroy_all
      reason = "Trial cancelled"
      first_emu_owner = business.enterprise_managed? ? business.find_first_emu_owner : nil
      first_emu_owner&.suspend(reason)
      owners = business.owners.where.not(id: first_emu_owner&.id)
      owners.each do |owner|
        business.remove_owner(owner, actor: nil, reason: reason, allow_removal_of_last_owner: true)
      end
      business.remove_billing_managers
    end

    business.business_teams.find_each do |team|
      team.members.each_slice(DELETE_BATCH_SIZE) do |users|
        with_write do
          team.bulk_remove_members(users:, caller_type: :business_team)
        end
      end
    end if business.erp_feature_enabled?(:enterprise_teams_crud)

    business.organizations.each do |organization|
      organization.members.each do |member|
        with_write do
          organization.remove_member(member, allow_last_admin_removal: true)
        end
      end

      organization.outside_collaborators.each do |outside_collaborator|
        with_write do
          organization.remove_outside_collaborator(outside_collaborator)
        end
      end
    end

    locked_organization_ids = business.organization_memberships.pluck(:organization_id)
    locked_organization_ids.each_slice(DELETE_BATCH_SIZE) do |slice|
      with_write do
        OrganizationInvitation.where(organization_id: slice).destroy_all
        RepositoryInvitation.for_organization_ids(slice).destroy_all
      end
    end
  end
end
