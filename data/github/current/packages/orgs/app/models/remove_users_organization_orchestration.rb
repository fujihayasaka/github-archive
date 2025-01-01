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

  job_start

  step :remove_organization_membership_entry do
    organizations.each do |org|
      users.each do |user|
        if EnterpriseTeam.enabled_for_organizations?(business: org.business)
          org.remove_organization_membership_entry_with_adder_type(user: user, derived: false, adder_type: :admin)
        else
          org.remove_organization_membership_entry(user: user, derived: false)
        end
      end
    end
  end

  step :conceal_member do
    organizations.each do |org|
      org.conceal_members(users)
    end
  end

  step :remove_all_member_requests do
    organizations.each do |org|
      users.each do |user|
        MemberFeatureRequest.remove_all_member_requests(user, org)
      end
    end
  end

  step :cancel_invitations do
    organizations.each do |org|
      users.each do |user|
        org.cancel_all_invitations_involving(user, force: true)
      end
    end
  end

  step :save_organization_settings do
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

  step :unlink_trade_screening_records do
    organizations.each do |org|
      users.each do |user|
        if user.has_trade_screening_record_linked_to_org?(organization: org)
          user.unlink_trade_screening_record_from_org(organization: org)
        end
      end
    end
  end

  step :remove_billing_managers do
    organizations.each do |org|
      users.each do |user|
        if org.billing_manager?(user)
          with_write { org.billing.remove_manager(user, actor: nil, reason: data[:reason]) }
        end
      end
    end
  end

  step :remove_moderators do
    organizations.each do |org|
      users.each do |user|
        with_write { org.moderation.remove_moderator(user, actor: nil, force: true) }
      end
    end
  end

  step :remove_direct_repo_access do
    organizations.each do |org|
      users.each do |user|
        org.remove_direct_repo_access(user) if data[:remove_direct_repo_access]
      end
    end
  end

  step :remove_direct_project_access do
    organizations.each do |org|
      users.each do |user|
        org.remove_direct_project_access(user)
      end
    end
  end

  step :remove_direct_project_next_access do
    organizations.each do |org|
      users.each do |user|
        becomes_outside_collaborator = \
          !data[:remove_direct_repo_access] && org.user_collaborates_on_any_repositories?(user.id)
        org.remove_direct_project_next_access(user) unless becomes_outside_collaborator
      end
    end
  end

  step :remove_users_from_business do
    if business.present? &&
      !T.must(business).enterprise_managed_user_enabled? &&
      !T.must(business).supports_unaffiliated_user_accounts?
      organizations.each do |org|
        users.each do |user|
          org.remove_user_from_business(user)
        end
      end
    elsif business.present?
      Licensing::SnapshotLicensesJob.perform_later(business)
    end
  end

  step :revoke_programmatic_access_grants do
    organizations.each do |org|
      users.each do |user|
        RevokeOrgMemberProgrammaticAccessGrantsJob.perform_later(org, user)
      end
    end
  end

  step :revoke_internal_app_authorizations do
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
        RevokeOrgMembershipAbilitiesJob.perform_later(org, user, data[:background_team_remove_member])
      end
    end
  end

  step :deny_fork_collab_state_for_user_pull_requests do
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
    organizations.each do |org|
      users.each do |user|
        with_write { org.remove_user_email_setting_for_org(user) }
      end
    end
  end

  step :unlink_saml_identities do
    organizations.each do |org|
      if org.saml_sso_enabled?
        ExternalIdentity.unlink_saml_identities(provider: org.saml_provider, user_ids: user_ids)
      end
    end
  end

  step :destroy_sponsors_listing_featured_items do
    organizations.each do |org|
      if org.sponsors_listing.present?
        users.each do |user|
          sponsors_listing_featured_item = T.must(org.sponsors_listing).featured_users.find_by(featureable_id: user.id)
          with_write { sponsors_listing_featured_item&.destroy }
        end
      end
    end
  end

  step :send_email_notification do
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
    end
  end

  step :clear_contribution_caches do
    users.each do |user|
      with_write { Contribution.clear_caches_for_user(user, context: "RemoveUsersOrganizationOrchestration") }
    end
  end

  step :update_business_license_usage do
    business&.update_license_usage unless data[:background_team_remove_member]
  end

  step :destroy_org_restricted_user_status do
    organizations.each do |org|
      users.each do |user|
        user.destroy_org_restricted_user_status(org)
      end
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
    if GitHub.mailchimp_enabled?
      organizations.each do |org|
        users.each do |user|
          MailchimpTeamListJob.perform_later(user: user, org: org)
        end
      end
    end
  end
end
