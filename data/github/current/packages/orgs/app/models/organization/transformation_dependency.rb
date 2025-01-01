# typed: strict
# frozen_string_literal: true

module Organization::TransformationDependency
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { Organization }

  FOLLOWER_RECALCULATION_BATCH_SIZE = 1000

  class_methods do
    # Extremely destructive and awesome method: transforms a normal
    # user account into an organization.
    #
    # Teams are created and users placed in them according to the
    # current collaborators. All teams initially are `pull` as that's
    # the implicit permission level of collaborators on normal
    # repositories as of writing.
    #
    # user          - The User object that is being transformed into an Organization.
    # owner         - The User object that will become the owner of the new Organization.
    # new_org_attrs - A hash of attributes to set on the new Organization.
    #
    # Returns nothing.
    # Raises TransformationFailed if there was validation error before the job
    # could be scheduled.
    sig { params(user: User, owner: T.nilable(User), new_org_attrs: T::Hash[String, Object]).void }
    def transform(user, owner, new_org_attrs = {})
      T.bind(self, T.class_of(Organization))

      if user.email.nil?
        raise Organization::TransformationFailed.new("Transform requires a primary email on the user account.")
      end

      if user.trade_compliance_delete_restriction?
        raise Organization::TransformationFailed.new("Transform requires an unrestricted account.")
      end

      if user.customer&.contacts&.any? { |contact| contact.has_delete_trade_restrictions? }
        raise Organization::TransformationFailed.new \
          "Transform requires an unrestricted account with unrestricted contact records."
      end

      if owner.nil?
        raise Organization::TransformationFailed.new("Transform requires an owner.")
      end

      if owner == user
        raise Organization::TransformationFailed.new("This user will become an organization and can't be an owner.")
      end

      unless user.user?
        raise Organization::TransformationFailed.new("Transform requires the user be a user.")
      end

      unless owner.user?
        raise Organization::TransformationFailed.new("Transform requires the owner be a user.")
      end

      if owned_org = user.organizations.detect { |org| org.last_admin?(user) }
        raise Organization::TransformationFailed.new(
          "Cannot transform user because user is the last owner of #{owned_org.display_login}"
        )
      end

      if owned_business = user.businesses(membership_type: :admin).detect { |business| business.last_owner?(user) }
        raise Organization::TransformationFailed.new(
          "Cannot transform user because user is the last owner of Enterprise account #{owned_business}."
        )
      end

      if start_transform(user)
        TransformUserIntoOrgJob.perform_later(user.id, owner.id, new_org_attrs)
      end
    end

    # Synchronous version of `Organization.transform`
    sig { params(user: User, owner: User, new_org_attrs: T::Hash[String, Object]).returns(Organization) }
    def transform!(user, owner, new_org_attrs = {})
      T.bind(self, T.class_of(Organization))

      if user.organization?
        end_transform(user)
        return Organization.find(user.id)
      end

      org = T.let(nil, T.nilable(Organization))

      user.trade_screening_record.destroy!
      user.customer&.contacts&.destroy_all

      OrganizationOrchestration.remove_users(
        actor: user,
        organizations: user.organizations.to_a,
        teams: [],
        users: [user],
        background_team_remove_member: false
      ).execute(synchronous: true)

      transaction do
        # Remove user as a collaborator from anything they're a member of
        # Note: This must be done *before* the User becomes an Organization, or the
        # `remove_member` ability revocation won't work.
        user.teams.each { |team| team.remove_member user }
        user.member_repositories.each { |repo| repo.remove_member user }
        RepositoryInvitation.where(invitee_id: user.id).find_each do |invitation|
          invitation.destroy
        end
        OrganizationInvitation.where(invitee_id: user.id, accepted_at: nil).find_each do |invitation|
          invitation.cancel(actor: user)
        end

        user.clear_issue_assignments # domain-isolation-query-violation:ignore:packages/issues (SELECT, UPDATE)
        user.destroy_reactions
        user.discussions.destroy_all
        user.discussion_comments.destroy_all
        user.two_factor_credential&.destroy
        user.u2f_registrations.destroy_all

        # remove user as admin from all Enterprise accounts
        admin_invitations = BusinessAdministratorInvitation
          .with_invitee_or_normalized_email(invitee: user, emails: user.emails.map(&:email))
          .pending
        admin_invitations.each { |invitation| invitation.cancel(actor: user) }
        user.businesses(membership_type: :admin).each do |business|
          business.remove_owner(user, actor: user)
        end
        user.businesses(membership_type: :billing_manager).each do |business|
          business.billing.remove_manager(user, actor: user)
        end
        user.businesses.each { |business| business.cleanup_removed_user(user, force: true) }

        # Revoke all OAuth tokens
        user.oauth_accesses.destroy_all

        # Uninstall all Integration Installations
        user.integration_installations.each { |installation| installation.uninstall(actor: user) }

        # Destroy all dashboard notices
        user.delete_notices

        # It's no longer possible to block this user since it's an org now
        user.ignored_by_users.destroy_all

        # All account succession agreements for that user are now nullified, now that they're an org.
        SuccessorInvitation.terminate_all(user)

        # Disable private profile, since it doesn't exist for orgs
        user.private_profile = false if user.private_profile?

        # The metamorphosis.
        previous_plan = user.plan.to_s
        user.type = "Organization"
        user.save!
        user.update!(new_org_attrs)

        if GitHub.billing_enabled?
          # Ensure we have enough seats to cover all collaborators
          user.seats = user.default_seats
          user.save!
        end

        # Fresh version of our new Organization.
        org = find(user.id)

        # Setting the Organization#creator skips sending OrganizationMailer#admin_added emails
        # till the transformation process is committed to the database
        org.creator = owner

        # Set up the owners team / admins
        org.admins = [owner]
        org.add_initial_admins

        # Ensure all our repos and forks know they're part of an organization.
        org.associate_repositories

        # Ensure all projects are updated to the correct owner type post-transfer.
        # This has to be done with User because owner is a polymorphic association
        # and we can't simply call `org.projects` until after this is complete
        org.associate_user_projects(user, owner)

        org.associate_user_memex_projects(user, owner)

        # Add collaborating team members to outside collaborators
        user.repositories.each do |repository|
          repository.teams.each do |team|
            team.members.each do |member|
              # Guard against trying to add the original User, which has now become an
              # Organization, which we have to test against `id`.
              next if member.id == user.id
              org.repositories.find(repository.id).add_member(
                member,
                action: Authorization.service.most_capable_action_between(actor: member, subject: repository)
              )
            end
          end
        end

        # Set up the default third-party application policy used for new orgs.
        org.initialize_application_policy

        # Set up the default attributes.
        org.sync_default_repository_permission!(actor: org)

        # Clean up some of the user's data that is no longer necessary.
        org.clear_transformed_user_data

        org.track_plan_change(org, GitHub::Plan.find!(previous_plan))

        # Disable if over plan limits
        org.enable_or_disable!

        # Rebuild the contributions data for the new org's repositories.
        org.rebuild_contributions

        # So everyone knows we've been transformed.
        end_transform(user)

        org.save
      end

      # THIS SHOULD ALWAYS BE THE LAST THING DONE IN THE `transform!` METHOD!
      # Perform any tasks that can only be completed after the org is transformed.
      org = find(user.id)
      org.perform_post_org_transformation_tasks

      # Tada.
      org
    ensure
      end_transform(user)
    end

    # The KV key used for keeping track of a user => org transform.
    sig { params(user: User).returns(String) }
    def transform_key(user)
      "org:transforming:#{user.id}"
    end

    # Begin transforming the passed user into an organization.
    sig { params(user: User).returns(T::Boolean) }
    def start_transform(user)
      Organization::KV.store.setnx(
        transform_key(user),
        Organization::TRANSFORM_FLAG,
        expires: Organization::TRANSFORM_FLAG_EXPIRY.from_now
      )
    rescue GitHub::KV::UnavailableError
      false # if KV is unavailable, we can't set the flag. Don't continue.
    end

    # Are we still transforming?
    sig { params(user: User).returns(T::Boolean) }
    def transforming?(user)
      !!Organization::KV.store.get(transform_key(user)).value { false }
    end

    # Complete transforming the passed user into an organization.
    #
    # Returns nothing.
    sig { params(user: User).void }
    def end_transform(user)
      Organization::KV.store.del(transform_key(user))
    rescue GitHub::KV::UnavailableError
      # Noop, ignore. Rely on expiration to clean up the flag.
    end
  end


  # Sets organization_id on all repos owned by the organization and
  # private forks owned by members of the org.
  sig { void }
  def associate_repositories
    repositories.each do |repo|
      # Preserve the (outside) collaborators.
      repo.update_organization remove_collaborators: false

      # Forks of private repos get associated with the org.
      next unless repo.private?

      repo.reload&.network&.sync_org_owned_private_network_with_forks

      repo.forks.each do |frk|
        frk.update_organization remove_collaborators: false
      end
    end
  end

  # Changes the owner type and sets up the project permissions
  # This will also re-sequence, so the project number may change if they have
  # deleted projects
  sig { params(user: User, owner: User).void }
  def associate_user_projects(user, owner)
    projects = user.projects.sort_by(&:number)
    projects.each do |project|
      project.transform_owner_type!(owner: self, new_creator: owner)
    end
  end

  # Changes the owner type and sets up the project permissions
  # This will also re-sequence, so the project number may change if they have
  # deleted projects
  # user is the objects that has been updated to type org
  sig { params(user: User, owner: User).void }
  def associate_user_memex_projects(user, owner)
    T.bind(self, Organization)

    projects = user.memex_projects.sort_by(&:number)
    projects.each do |project|
      project.transform_owner_type!(new_owner: self, new_creator: owner)
    end
  end

  # Removes user data which is no longer necessary now that the user
  # has been transformed into an organization, such as public keys and
  # passwords.
  sig { void }
  def clear_transformed_user_data
    T.bind(self, Organization)

    self.password = "n0n3:#{Time.now.to_i}"
    self.gravatar_email = gravatar_email || email
    self.billing_email  = billing_email || email
    self.gh_role = nil
    save!

    sessions.destroy_all
    public_keys.clear

    emails.clear
    email_roles.clear

    # Unstar all repos and Gists.
    (starred_repositories + starred_gists).each do |starrable|
      unstar(starrable)
    end

    # Orgs don't have review requests
    clear_review_requests

    # Orgs don't have notifications.
    Notifications::Subscriptions.async_delete_user_subscriptions(T.let(id, Integer))

    # Orgs can't login, so they can't see the interaction warning
    T.must(interaction_setting).destroy if interaction_setting

    ExternalIdentity.cleanup_user(self, organization_transform: true)

    # If they have a profile we want to remove everything except the
    # allow listed profile fields. This way an organization does not
    # remain hireable, for instance.
    #
    # Also sets profile display staff badge to false, since orgs cannot
    # have staff badges
    if profile
      allowlist = %w( name blog location )
      denylist = Profile.column_names - allowlist

      denylist.each do |field|
        method = "profile_#{field}="
        send(method, nil) if respond_to?(method) # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
      end

      T.must(profile).display_staff_badge = false
      T.must(profile).readme_opt_in = false

      T.must(profile).save
    end
  end

  # Public: Do anything that was deferred until after this organization was transformed.
  sig { void }
  def perform_post_org_transformation_tasks
    T.bind(self, Organization)

    instrument :transform, owner: admins.first.to_s, tos_sha: TosAcceptance.current_sha

    # NB: Need to force the BT update since the update catches
    # to see if there are changes on the relevant fields.
    update_external_subscription!(force: true)

    # ensure org has initial set of default labels
    populate_initial_user_labels

    if GitHub.single_business_environment? && GitHub.global_business
      # Ensure the new org is added to the global enterprise account.
      GitHub.global_business.add_organization(self)
    end

    # Notify the org owner that they have been added as an admin
    admins.each do |admin|
      OrganizationMailer.admin_added(admin, self, nil).deliver_later
    end

    # Setup the default issue types for the new org
    unless GitHub.flipper[:default_issue_types_job_killswitch].enabled?
      SetupIssueTypesForOrganizationJob.perform_later(org: self)
    end

    if feature_enabled?(:collaborator_cache_write) || GitHub.flipper[:collaborator_cache_write].enabled?
      OrganizationCollaboratorBackfillJob.perform_later(org: self)
    end

    clear_following_and_recalculate_counters
  end

  private

  sig { void }
  def clear_following_and_recalculate_counters
    following_records = Following.followed_by(self)
    following_ids = following_records.pluck(:following_id)
    following_records.destroy_all

    following_ids.each_slice(FOLLOWER_RECALCULATION_BATCH_SIZE) do |user_ids|
      RecalculateUserFollowersCacheJob.perform_later(user_ids: user_ids)
    end
  end
end
