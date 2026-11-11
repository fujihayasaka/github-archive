# typed: true
# frozen_string_literal: true

class RemoveUsersOrganizationOrchestration < OrganizationOrchestration
  include GitHub::Memoizer

  # TODO:
  #
  # Optimise bulk removal more.
  #
  # This has been implemented to be feature complete with Organization#remove_member! and does not yet use
  # optimised bulk removal for all steps.

  # Delay before enqueuing job to remove unaffiliated members from business.
  # This allows time for database replication and ensures consistency before cleanup.
  REMOVE_UNAFFILIATED_MEMBER_DELAY = 60.seconds

  job_start

  step :remove_organization_membership_entry do
    organizations.each do |org|
      etv1_enabled_for_org = EnterpriseTeam.enabled_for_organizations?(business: org.business)

      if org.feature_flag_enabled?(:bulk_remove_organization_membership_entry_in_batches, default: false) && !etv1_enabled_for_org
        org.bulk_remove_organization_membership_entry(users: users.to_a, derived: false)
      else
        users.each do |user|
          if etv1_enabled_for_org
            org.remove_organization_membership_entry_with_adder_type(user: user, derived: false, adder_type: :admin)
          else
            org.remove_organization_membership_entry(user: user, derived: false)
          end
        end
      end
    end
  end

  step :conceal_member do
    return if data[:users_retain_business_team_indirect_access]
    Organization.conceal_members(org_ids: organization_ids, user_ids: user_ids)
  end

  step :remove_all_member_requests do
    return if data[:users_retain_business_team_indirect_access]
    in_batches(teams: false) do |user_ids, organization_ids|
      request_ids = MemberFeatureRequest.where(requester_id: user_ids, request_entity_type: "User", request_entity_id: organization_ids).pluck(:id)
      next unless request_ids.any?
      MemberFeatureRequest.transaction do
        with_write { MemberFeatureRequest.where(id: request_ids).delete_all }
      end
    end
  end

  step :cancel_invitations do
    return if data[:users_retain_business_team_indirect_access]
    in_batches(teams: false) do |user_ids, organization_ids|
      OrganizationInvitation.where(OrganizationInvitation.pending.where_values_hash).where(organization_id: organization_ids).where(inviter_id: user_ids).includes(:inviter).each { |i| i.cancel(actor: i.inviter) }
      RepositoryInvitation.joins(:repository).where(repositories: { owner_id: organization_ids }, inviter_id: user_ids).includes(:inviter).each { |i| i.cancel!(actor: i.inviter, force: true) }
      OrganizationInvitation.where(OrganizationInvitation.pending.where_values_hash).where(organization_id: organization_ids, invitee_id: user_ids).includes(:invitee).each { |i| i.cancel(actor: i.invitee) }
      RepositoryInvitation.joins(:repository).where(repositories: { owner_id: organization_ids }, invitee_id: user_ids).includes(:invitee).each { |i| i.cancel!(actor: i.invitee, force: true) }
    end
  end

  step :save_organization_settings do
    return if data[:users_retain_business_team_indirect_access]
    if data[:save_settings] == true
      organizations.each do |org|
        users.each do |user|
          org.save_organization_settings_for_user(user)
        end
      end
    end
  end

  step :cancel_team_membership_requests do
    organizations.each do |org|
      org.cancel_team_membership_requests_for(user_ids)
    end
  end

  step :unlink_billing_contacts do
    return if data[:users_retain_business_team_indirect_access]
    organizations.each do |org|
      users.each do |user|
        if org.has_linked_billing_contact_to_actor?(actor: user)
          org.unlink_billing_contact(actor: user)
        end
      end
    end
  end

  step :remove_billing_managers do
    return if data[:users_retain_business_team_indirect_access]
    organizations.each do |org|
      users.each do |user|
        if org.billing_manager?(user)
          with_write { org.billing.remove_manager(user, actor: nil, reason: data[:reason]) }
        end
      end
    end
  end

  step :remove_moderators do
    return if data[:users_retain_business_team_indirect_access]
    organizations.each do |org|
      users.each do |user|
        with_write { org.moderation.remove_moderator(user, actor: nil, force: true) }
      end
    end
  end

  step :remove_direct_repo_access do
    return unless data[:remove_direct_repo_access]
    return if data[:users_retain_business_team_indirect_access]
    organizations.each do |org|
      org.remove_direct_repo_access_for(users, skip_organization_collaborator_update: true, actor: actor)
    end
  end

  # Look for advisories collaborators who might be missing in the remove_direct_repo_access step since
  # the user may be a member of the org but not a collaborator of the repositories in the org.
  step :remove_repo_advisories_collaborators do
    return if data[:users_retain_business_team_indirect_access]
    with_write { Repository::AdvisoryAbilityManager.remove_collaborators_from_organizations(collabs: users, organizations: organizations) }
  end

  step :remove_organization_collaborators do
    return if data[:users_retain_business_team_indirect_access]
    return unless data[:remove_direct_repo_access]
    with_write { OrganizationCollaborator.where(organization_id: organization_ids, user_id: user_ids).destroy_all }
  end

  step :remove_direct_project_access do
    return if data[:users_retain_business_team_indirect_access]
    organizations.each do |org|
      users.each do |user|
        org.remove_direct_project_access(user)
      end
    end
  end

  step :remove_direct_project_next_access do
    return if data[:users_retain_business_team_indirect_access]
    organizations.each do |org|
      user_ids_to_remove = users.filter_map do |user|
        next if !data[:remove_direct_repo_access] && org.user_collaborates_on_any_repositories?(user.id)
        user.id
      end

      BulkRemoveOrgMemberProjectsNextAccessJob.perform_now(org, user_ids_to_remove)
    end
  end

  step :cleanup_removed_users do
    return if GitHub.single_business_environment? || data[:users_retain_business_team_indirect_access]
    return unless business.present? && T.must(business).remove_user_accounts_when_removing_last_org_membership?

    users.each do |user|
      RemoveUnaffiliatedMemberFromBusinessJob.set(wait: REMOVE_UNAFFILIATED_MEMBER_DELAY).perform_later(
        T.must(business),
        user,
        reason: "removed user from all organizations in enterprise"
      )
    end
  end

  step :revoke_programmatic_access_grants do
    return if data[:users_retain_business_team_indirect_access]
    organizations.each do |org|
      users.each do |user|
        RevokeOrgMemberProgrammaticAccessGrantsJob.perform_later(org, user)
      end
    end
  end

  step :revoke_internal_app_authorizations do
    return if data[:users_retain_business_team_indirect_access]
    organizations.each do |org|
      users.each do |user|
        if org.removing_last_organization_membership_in_business_for?(user)
          RevokeInternalAppAuthorizationsJob.perform_later(organization_id: org.id, user_ids: [user.id])
        end
      end
    end
  end

  step :revoke_org_membership_abilities do
    organizations.each do |org|
      users.each do |user|
        Ability.throttle do
          with_write { org.remove_member_without_callbacks_and_notifications(user, background: false) }
        end

        # Org team membership cleanup is the only contract guaranteeing the user is
        # detached from `Team` rows scoped to this org. Historically this was deferred
        # to `RevokeOrgMembershipAbilitiesJob.perform_later`, which is enqueued via the
        # standard async path. If that enqueue is silently lost (e.g. a transient DB
        # connectivity blip on the jobs write), the user is left as a "ghost" member
        # of their org teams while appearing removed from the org. See
        # github/enterprise-primitives#5290 / #5072.
        #
        # When `:inline_revoke_org_membership_team_cleanup` is enabled, we perform the
        # team-membership cleanup inline within this orchestration step so it benefits
        # from the orchestration's step retry envelope. The async job is still enqueued
        # to handle the remaining dependent work (forks, watched repos, role grants,
        # etc.) — that work is non-membership and its idempotent re-run is safe.
        if data[:users_retain_business_team_indirect_access] ||
            inline_team_cleanup_enabled_for?(org)
          # Mirror RevokeOrgMembershipAbilitiesJob#perform: capture the user's
          # currently-visible repositories *before* tearing down team membership
          # so the REPOSITORY_ACCESS_CHANGED event downstream consumers rely on
          # (e.g. codespaces cleanup) sees the pre-cleanup access list. Without
          # this, removing the team rows here would cause the async job's own
          # `visible_repositories_for` lookup to come back empty.
          inline_repo_ids = unless data[:users_retain_business_team_indirect_access]
            org.visible_repositories_for(user, batched: true).pluck(:id)
          end

          org.teams_for(user).each do |team|
            with_write { team.remove_member(user, force: true, send_notification: false, queue_delete_jobs: false) }
          end

          unless data[:users_retain_business_team_indirect_access]
            GlobalInstrumenter.instrument(GlobalEvents::User::REPOSITORY_ACCESS_CHANGED, {
              user: user,
              repository_ids: inline_repo_ids,
            })
          end
        end

        unless data[:users_retain_business_team_indirect_access]
          RevokeOrgMembershipAbilitiesJob.perform_later(org, user, data[:background_team_remove_member], revoke_performed_in_orchestration: true)
        end
      end
    end
  end

  step :deny_fork_collab_state_for_user_pull_requests do
    return if data[:users_retain_business_team_indirect_access]
    organizations.each do |org|
      users.each do |user|
        DenyForkCollabStateForUserPullRequestsJob.perform_later(
          user_id: user.id,
          resource_id: org.id,
          resource_class: org.class.name
        )
      end
    end
  end

  step :remove_org_user_email_settings do
    return if data[:users_retain_business_team_indirect_access]
    organizations.each do |org|
      users.each do |user|
        with_write { org.remove_user_email_setting_for_org(user) }
      end
    end
  end

  step :unlink_saml_identities do
    return if data[:users_retain_business_team_indirect_access]
    organizations.each do |org|
      if org.saml_sso_enabled?
        ExternalIdentity.unlink_saml_identities(provider: org.saml_provider, user_ids: user_ids)
      end
    end
  end

  step :destroy_sponsors_listing_featured_items do
    return if data[:users_retain_business_team_indirect_access]
    in_batches(teams: false) do |user_ids, organization_ids|
      listing_ids = SponsorsListing.where(sponsorable_id: organization_ids).pluck(:id)
      next unless listing_ids.any?
      item_ids = SponsorsListingFeaturedItem.where(sponsors_listing_id: listing_ids, featureable_id: user_ids).pluck(:id)
      next unless item_ids.any?
      with_write { SponsorsListingFeaturedItem.where(id: item_ids).destroy_all }
    end
  end

  step :send_email_notification do
    return if data[:users_retain_business_team_indirect_access]
    organizations.each do |org|
      users.each do |user|
        if data[:send_notification] && !user.suspended?
          OrganizationMailer.removed_from_org(user, org, data[:reason]&.to_s).deliver_later
        end
      end
    end
  end

  step :instrument_removal do
    organizations.each do |org|
      users.each do |user|
        instrument_options = {
          user: user,
          reason: data[:reason],
          membership_types: data[:membership_types][org.id][user.id].map(&:to_s),
          actor: actor,
        }

        if GitHub.context[:hide_staff_user] && GitHub.guard_audit_log_staff_actor?
          instrument_options.merge!(GitHub.guarded_audit_log_staff_actor_entry(actor))
          # GlobalInstrumenter requires a real user
          instrument_options[:actor] = User.staff_user
        end

        org.instrument(:remove_member, instrument_options)
        options = instrument_options.merge(org: org, action: :remove)
        GlobalInstrumenter.instrument "org.remove_member", options
      end

      GlobalInstrumenter.instrument("organization.remove_members", {
        organization: org,
        actor: actor,
        user_ids: users.map(&:id),
        reason: data[:reason]
      })
    end
  end

  step :clear_contribution_caches do
    return if data[:users_retain_business_team_indirect_access]
    users = self.users.to_a
    return if users.none?
    with_write { Contribution.bulk_clear_caches_for_users(users, context: "RemoveUsersOrganizationOrchestration") }
  end

  step :update_business_license_usage do
    return if data[:users_retain_business_team_indirect_access]
    business&.update_license_usage
  end

  step :destroy_org_restricted_user_status do
    return if data[:users_retain_business_team_indirect_access]
    in_batches(teams: false) do |user_ids, organization_ids|
      status_ids = UserStatus.where(user_id: user_ids, organization_id: organization_ids).pluck(:id)
      next unless status_ids.any?
      with_write { UserStatus.where(id: status_ids).destroy_all }
    end
  end

  step :remove_org_admin_abilities do
    organizations.each do |org|
      users.each do |user|
        if org.admins.include?(user)
          # This is important! If the user is an admin, then we need to synchronously
          # make them not an admin, otherwise prevent_removal_of_last_admin! does not work correctly.
          # see https://github.com/github/teams_and_orgs/issues/64
          with_write { Ability.revoke(user, org, background: false) }
          org.admins.reload
        end
      end
    end
  end

  step :update_mailchimp do
    return if data[:users_retain_business_team_indirect_access]
    if MailchimpTeamListJob.enabled?
      organizations.each do |org|
        users.each do |user|
          MailchimpTeamListJob.perform_later(user: user, org: org)
        end
      end
    end
  end

  step :synchronize_user_search_index do
    return if data[:users_retain_business_team_indirect_access]
    users.each do |user|
      user.synchronize_search_index
    end
  end

  step :revoke_org_member_copilot_space_access do
    return if GitHub.enterprise?
    return if data[:users_retain_business_team_indirect_access]
    organizations.each do |org|
      users.each do |user|
        CopilotSpaces::RevokeOrgMemberCopilotSpaceAccessJob.perform_later(org, user)
      end
    end
  end

  private

  # Returns true when org team membership cleanup should be performed inline
  # within the `revoke_org_membership_abilities` step instead of being deferred
  # to `RevokeOrgMembershipAbilitiesJob`. The flag is checked on the
  # organization first and then on its parent business so it can be rolled out
  # at either level.
  def inline_team_cleanup_enabled_for?(org)
    return true if org.feature_flag_enabled?(:inline_revoke_org_membership_team_cleanup, default: false)
    org.business&.feature_flag_enabled?(:inline_revoke_org_membership_team_cleanup, default: false) || false
  end
end
