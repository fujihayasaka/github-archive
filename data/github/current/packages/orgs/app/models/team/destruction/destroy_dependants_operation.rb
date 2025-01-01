# typed: true
# frozen_string_literal: true

module Team::Destruction

  # When a set of teams is removed in bulk, we need to destroy their dependants
  # A common case in which we destroy teams in bulk is when we remove a team
  # in that has descendants. In that situation, all the dependants
  # for the team being destroyed and their descendants need to be destroyed.
  #
  # Removing team dependants imply:
  # - Destroying their ExternalGroup
  # - Destroying their TeamMembershipRequests
  # - Destroying their pending TeamInvitations
  # - Destroying their LDAP Mappings
  # - Destroying their discussion posts
  # - Destroying their subscriptions
  # - Revoking their users' permissions, which in turn includes:
  #  - clearing the team's abilities
  #  - sending webhook to inform integrators about the members being removed from the team
  #  - enqueing jobs to clear membership information, like assigned issues, watched
  #    repositories, etc. For those repos that were owned by the team. See `Jobs::ClearTeamMemberships`
  #  - sending emails to the users to inform them about being removed from the team
  #  - clearing fork information
  #
  class DestroyDependantsOperation
    include BusinessesHelper

    TEAM_BATCH_SIZE   = 20
    MEMBER_BATCH_SIZE = 100
    MAX_THROTTLE_RETRIES = 5.freeze
    DESTROY_BATCH_SIZE = 100.freeze

    attr_reader :org_ids, :team_ids_to_info, :orgs

    # Creates a new instance of this command object.
    #
    # Params:
    #
    #  - org_ids: the organizations owning the teams which dependants are going to be destroyed.
    #  - team_ids_to_info: is a hash where the keys are the team ids to be destroyed and the values
    #    is some of the team's information that's needed to perform the action. This information has to
    #    be provided, as the teams themselves were deleted already if this was invoked from
    #    Team::Destruction::DestroyOperation. As numeric and symbol values in hashes are serialized as
    #    strings, this constructor also converts the keys to integers and the values's keys to symbols.
    #    An example value for `team_ids_to_info` is:
    #
    #     {
    #      "9381" => {"name" => "Engineering", "legacy_owners" => true },
    #      "6173" => {"name" => "Platform", "legacy_owners" => false }
    #     }
    #
    def initialize(org_ids, team_ids_to_info, options = {})
      @options = options
      @org_ids = Array(org_ids) # Ensure org_ids is always an array
      @orgs = Organization.where(id: @org_ids).to_a
      @team_ids_to_info = Hash[team_ids_to_info.map { |k, v| [k.to_i, v.symbolize_keys] }]
    end

    def execute(with_instrumentation: true)
      all_team_ids = team_ids_to_info.keys

      all_team_ids.each_slice(TEAM_BATCH_SIZE) do |team_ids|
        team_ids_to_info_slice = team_ids_to_info.slice(*team_ids)

        measuring(:enqueue_clean_up_errant_abilities_jobs, team_ids)
        measuring(:instrument_destruction, orgs, team_ids_to_info_slice) if with_instrumentation
        measuring(:destroy_ldap_mappings, team_ids) if GitHub.enterprise?
        measuring(:destroy_group_mappings, team_ids)
        measuring(:destroy_membership_requests, team_ids)
        measuring(:destroy_requests_to_parent, team_ids)
        measuring(:destroy_requests_to_be_child, team_ids)
        measuring(:destroy_team_invitations, org_ids, team_ids)
        measuring(:revoke_user_permissions, orgs, team_ids, team_ids_to_info_slice)
        measuring(:destroy_discussion_posts, team_ids)
        measuring(:destroy_team_dashboards, team_ids)
        measuring(:destroy_subscriptions, team_ids)
        measuring(:destroy_review_requests, team_ids)
        measuring(:destroy_user_roles, team_ids)
        measuring(:destroy_business_team_org_assignments, team_ids)
      end
    end

    private

    def measuring(operation, *args, &block)
      start = Time.now
      result = T.unsafe(self).send(operation, *args, &block)
      ms = (Time.now - start) * 1000
      GitHub.dogstats.distribution("team.destruction.destroy_dependants_operation.dist.duration", ms, tags: ["operation:#{operation}"])
      result
    end

    def instrument_destruction(orgs, team_ids_to_info)
      # business teams aren't sent with_instrumentation, so this won't run for them
      org = orgs.first
      return unless org

      team_ids_to_info.each do |team_id, info|
        # skip instrumenting enterprise managed teams
        next if info[:enterprise_team_managed] && EnterpriseTeam.enabled_for_organizations?(business: org.business)

        combined_slug = "#{org.login}/#{info[:slug]}"
        GitHub.instrument("team.destroy", {
          team: combined_slug,
          team_id: team_id,
          org: org,
          ldap_mapped: info[:ldap_mapped],
          note: "Team #{combined_slug}",
        })
      end
    end

    def destroy_group_mappings(team_ids)
      records = Team::GroupMapping.where(team_id: team_ids)
      batch_destroy(records: records)
    end

    def destroy_membership_requests(team_ids)
      records = TeamMembershipRequest.where(team_id: team_ids)
      batch_destroy(records: records)
    end

    def destroy_requests_to_parent(team_ids)
      records = TeamChangeParentRequest.where(parent_team_id: team_ids)
      batch_destroy(records: records)
    end

    def destroy_requests_to_be_child(team_ids)
      records = TeamChangeParentRequest.where(child_team_id: team_ids)
      batch_destroy(records: records)
    end

    def destroy_team_invitations(org_id, team_ids)
      records = TeamInvitation.joins(:organization_invitation)
        .where("organization_invitations.organization_id": org_id, team_id: team_ids)
        .where("organization_invitations.accepted_at": nil, "organization_invitations.cancelled_at": nil)
      batch_destroy(records: records)
    end

    def destroy_ldap_mappings(team_ids)
      records = LdapMapping.where(subject_id: team_ids, subject_type: "Team")
      batch_destroy(records: records)
    end

    def destroy_user_roles(team_ids)
      records = UserRole.where(
        actor_id: team_ids,
        actor_type: business_team_operation? ? "BusinessTeam" : "Team"
      )
      batch_destroy(records: records)
    end

    def destroy_business_team_org_assignments(team_ids)
      return unless business_team_operation?
      records = BusinessTeamOrgAssignment.where(team_id: team_ids)
      batch_destroy(records: records)
    end

    def revoke_user_permissions(orgs, team_ids, team_ids_to_info)
      member_ids_by_team_id = Hash.new { |h, k| h[k] = [] }
      ::Ability.distinct.where(
        actor_type: "User",
        subject_id: team_ids,
        subject_type: business_team_operation? ? "BusinessTeam" : "Team",
        priority: ::Ability.priorities[:direct],
      ).pluck(:subject_id, :actor_id).each do |subject_id, actor_id|
        member_ids_by_team_id[subject_id] << actor_id
      end

      repo_ids_by_team_id = Hash.new { |h, k| h[k] = [] }
      ::Ability.distinct.where(
        actor_type: business_team_operation? ? "BusinessTeam" : "Team",
        actor_id: team_ids,
        subject_type: "Repository",
        priority: ::Ability.priorities[:direct],
      ).pluck(:actor_id, :subject_id).each do |actor_id, subject_id|
        repo_ids_by_team_id[actor_id] << subject_id
      end

      measuring(:clear_abilities, team_ids)

      team_ids_to_info.each do |team_id, team_info|
        member_ids = member_ids_by_team_id[team_id]
        repo_ids = repo_ids_by_team_id[team_id]

        measuring(:queue_fork_cleanup, repo_ids, member_ids)

        team_name     = team_info[:name]
        legacy_owners = team_info[:legacy_owners]

        next if !orgs.first && !business_team_operation?

        repo_ids.each do |repo_id|
          GitHub.instrument("team.remove_repository", {
            team: team_name,
            team_id: team_id,
            org: business_team_operation? ? nil : orgs.first,
            repo_id: repo_id,
            repo: Repositories::Public.get_active_or_deleted(repo_id),
            ldap_mapped: team_info[:ldap_mapped]
          })
        end

        User.where(id: member_ids).find_each(batch_size: MEMBER_BATCH_SIZE) do |member|
          orgs.each do |org|
            measuring(:send_hookshot_event, org, member.id, member.login, team_id, team_name)
            measuring(:queue_clear_team_memberships, org, member.id, repo_ids)
          end

          if business_team_operation?
            # TODO: We need a business_team removal notification
            nil
          else
            measuring(:send_removal_notification, orgs.first, member, team_id, team_name, repo_ids, legacy_owners) unless team_info[:enterprise_team_managed]
          end
        end
      end

      # Cleanup organization memberships derived from external group teams and enterprise managed teams
      orgs.each do |org|
        if org&.business
          measuring(:destroy_organization_membership_entries, org, team_ids)
        end
      end
    end

    def business_team_operation?
      @options[:business].present?
    end

    def destroy_organization_membership_entries(org, team_ids)
      # delete the external group teams
      records = ExternalGroupTeam.where(team_id: team_ids)
      batch_delete(records: records)

      # identify users with derived org memberships based on team_ids
      business = org.business
      derived_org_membership_entries = ActiveRecord::Base.connected_to(role: :reading) do
        OrganizationMembershipEntry.where(organization_id: org.id, adder_id: team_ids, adder_type: [:external_team, :enterprise_team])
      end
      derived_org_members_ids = derived_org_membership_entries.map(&:user_id)

      # delete derived org membership entries associated with team_ids
      batch_destroy(records: derived_org_membership_entries)

      users = User.batched_scope(:id, values: derived_org_members_ids).to_a

      # if the user only has derived organization membership via a team (that was just removed above)
      # remove the user from the organization
      users.each do |user|
        unless org.prevent_removal_of_scim_managed_user?(user: user, reason: :any, db_connection: :writing)
          begin
            # If a user from an org is removed because an enterprise team is destroyed, don't notify users
            # We know if there was an enterprise team entry for the team, the team is enterprise-managed
            send_notification = derived_org_membership_entries.none? { |entry| entry.adder_type == "enterprise_team" }
            org.remove_member(user, send_notification: send_notification)
          rescue Organization::NoAdminsError, Organization::UnableToRemoveEmuError, Organization::UnableToRemoveEnterpriseTeamMemberError, Organization::BusinessTeamsDependency::UnableToRemoveBusinessTeamMemberError
          end
        end
      end
    end

    def destroy_discussion_posts(team_ids)
      records = DiscussionPost.where(team_id: team_ids)
      batch_destroy(records: records)
    end

    def destroy_team_dashboards(team_ids)
      records = TeamDashboard.where(team_id: team_ids)
      batch_destroy(records: records)
    end

    def destroy_review_requests(team_ids)
      records = ReviewRequest.where(reviewer_id: team_ids, reviewer_type: "Team")
      batch_destroy(records: records)
    end

    def destroy_subscriptions(team_ids)
      team_ids.each do |team_id|
        Notifications::Subscriptions.async_delete_list_subscriptions(Notifications::Subject.new(type: business_team_operation? ? "BusinessTeam" : "Team", id: team_id))
      end
    end

    def clear_abilities(team_ids)
      Authorization.service.clear_abilities_for_multiple_participants(
        participant_type: business_team_operation? ? BusinessTeam : Team,
        participant_ids: team_ids
      )
    end

    def send_hookshot_event(org, member_id, member_login, team_id, team_name)
      Hook::Event::MembershipEvent.queue(action: :removed,
                                         member_id: member_id,
                                         member_login: member_login,
                                         team_id: team_id,
                                         team_name: team_name,
                                         organization_id: org.id,
                                         actor_id: GitHub.context[:actor_id])
    end

    def queue_clear_team_memberships(org, member_id, repo_ids)
      Team.queue_clear_team_memberships(repo_ids, org.id, { user: member_id })
    end

    def send_removal_notification(org, member, team_id, team_name, repo_ids, legacy_owners)
      return unless repo_ids.any?

      return if member.suspended?

      # Do not change to #deliver_later, this mailer is currently run in the
      # DestroyTeamDependants job
      TeamsMailer.removed_from_team(
        member,
        team_name,
        org,
        legacy_owner: !!legacy_owners,
        team_destroyed: true,
      ).deliver_now
    end

    def queue_fork_cleanup(repo_ids, member_ids)
      Team.queue_fork_cleanup(repo_ids, member_ids)
    end

    def enqueue_clean_up_errant_abilities_jobs(team_ids)
      # Clean up any errant abilities still remaining after 1 hour and 12 hours
      team_ids.each do |team_id|
        CleanUpDeletedTeamAbilitiesJob.set(wait_until: 1.hour.from_now).perform_later(team_id)
        CleanUpDeletedTeamAbilitiesJob.set(wait_until: 12.hours.from_now).perform_later(team_id)
      end
    end

    def batch_delete(records:)
      records.in_batches(of: DESTROY_BATCH_SIZE) do |batched_scope|
        records.klass.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
          batched_scope.delete_all
        end
      end
    end

    def batch_destroy(records:)
      records.in_batches(of: DESTROY_BATCH_SIZE) do |batched_scope|
        records.klass.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
          batched_scope.destroy_all
        end
      end
    end
  end
end
