# typed: true
# frozen_string_literal: true

class RemoveMembersBusinessOrchestration < BusinessOrchestration
  job_start

  step :remove_abilities do
    data_roles_lost = {}
    data_organizations_removed_from_ids = {}

    users.each do |user|
      roles_lost = Set.new
      organizations_removed_from = Set.new

      # NOTE: This is not used in production currently. It is here to support Enterprise Security Manager development,
      # which includes GHES or Proxima staffship
      bulk_remove_members = EnterpriseTeam.enabled_for_organizations?(business: user.business)
      if bulk_remove_members
        ability_ids, org_ids = Ability.where(
          actor_type: "User",
          actor_id: user.id,
          subject_type: "Organization",
          subject_id: T.must(business).organization_ids
        ).pluck(:id, :subject_id).transpose
        T.must(business).remove_abilities_from_business(ability_ids, actor: actor)
        organizations_removed_from = Organization.where(id: org_ids).to_set
      end

      T.must(business).organizations.each do |organization|
        # remove direct or pending member organization members
        if (!bulk_remove_members && organization.direct_member?(user, include_indirect_abilities: false)) ||
          organization.pending_members.include?(user)

          roles_lost.add :member
          organizations_removed_from.add organization
          with_write { organization.remove_member(user, send_notification: false, background_team_remove_member: true) }
        end
        # remove access to repos they're outside collaborators on
        if organization.user_is_outside_collaborator?(user.id)
          roles_lost.add :outside_collaborator
          organizations_removed_from.add organization
          with_write { organization.remove_outside_collaborator!(user, send_notification: false) }
        end
        # remove pending outside collaborator invitations
        if organization.repository_invitations.where(invitee: user).exists?
          roles_lost.add :outside_collaborator
          repository_ids = organization.repositories.pluck(:id)
          with_write { RepositoryInvitation.cancel_all_invitations_involving(user: user, repo_ids: repository_ids) }
        end
        # remove organization billing managers
        if organization.billing.manager?(user)
          roles_lost.add :billing_manager
          with_write { organization.billing.remove_manager(user, actor: actor) }
        end
      end

      data_roles_lost[user.id] = roles_lost.to_a
      data_organizations_removed_from_ids[user.id] = organizations_removed_from.map(&:id)
    end

    data[:roles_lost] = data_roles_lost
    data[:organizations_removed_from_ids] = data_organizations_removed_from_ids
  end

  step :remove_owners do
    users.each do |user|
      is_owner = T.must(business).owner?(user)
      pending_owner_invitation = T.must(business).pending_admin_invitation_for(user, role: "owner")
      if is_owner || pending_owner_invitation
        data[:roles_lost][user.id] << :owner
        with_write do
          if is_owner
            T.must(business).remove_owner(user, actor: actor, send_notification: false)
          elsif pending_owner_invitation
            pending_owner_invitation.cancel(actor: user)
          end
        end
      end
    end
  end

  step :remove_billing_managers do
    users.each do |user|
      is_billing_manager = T.must(business).billing_manager?(user)
      pending_billing_manager_invitation = T.must(business).pending_admin_invitation_for(user, role: "billing_manager")
      if is_billing_manager || pending_billing_manager_invitation
        data[:roles_lost][user.id] << :billing_manager
        with_write do
          if is_billing_manager
            T.must(business).billing.remove_manager(user, actor: actor, send_notification: false)
          elsif pending_billing_manager_invitation
            pending_billing_manager_invitation.cancel(actor: user)
          end
        end
      end
    end
  end

  step :send_email_notifications do
    return unless data[:send_notification]

    users.each do |user|
      T.must(business).send_member_removed_email_notification(
        user,
        data[:roles_lost][user.id],
        Organization.where(id: data[:organizations_removed_from_ids][user.id]).to_a
      )
    end
  end

  step :cleanup_removed_users do
    with_write { T.must(business).cleanup_removed_users(user_ids, force: true) }
  end

  step :instrument do
    users.each do |user|
      T.must(business).instrument_remove_member(user: user, actor: actor, reason: data[:reason])
    end
  end
end
