# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: strict
# frozen_string_literal: true

class EnterpriseTeamOrganizationReconciliationRunnerJob < ApplicationJob
  include SecurityCenter::FanoutThrottler
  include GitHub::Memoizer

  USER_NOT_FOUND_METRIC = "enterprise_team_organization_reconciliation.user_not_found"
  ADD_STATUS_NOT_FOUND_METRIC = "enterprise_team_organization_reconciliation.add_status_not_found"
  MAX_CONCURRENT_JOBS = 1
  RESTRAINT_LOCK_TTL = T.let(5.minutes, Integer)
  LOCK_KEY = "enterprise_team_organization_reconciliation_runner_job:"

  queue_as :enterprise_team_organization_reconciliation_runner

  retry_on_dirty_exit
  retry_on_recoverable_exceptions
  retry_on GitHub::Restraint::UnableToLock, wait: ->(_executions) { (rand(30..300)).seconds }, attempts: :unlimited

  sig do params(
    enterprise_team: EnterpriseTeam,
    mappings: T::Array[EnterpriseTeamOrganizationMapping],
    out_of_sync_time: Time).void
  end
  def perform(enterprise_team:, mappings:, out_of_sync_time: Time.zone.now)
    # Extra protection to ensure it doesn't run unintentionally. FF is fully off. It can still run for GHES only
    return unless EnterpriseTeam.enabled_for_organizations?(business: enterprise_team.business)
    @updated_users = T.let([], T.nilable(T::Array[T::Array[Integer]]))

    acquire_global_job_lock!(enterprise_team:) do
      GitHub.logger.info(
        "info.message" => "Starting enterprise_team_organization_reconciliation_runner_job for #{mappings.size} mappings",
        "gh.enterprise_team.id" => enterprise_team.id,
      )

      if enterprise_team.sync_to_organizations?
        user_ids = enterprise_team.member_user_ids
        org_team_mappings = mappings.pluck(:organization_id, :team_id)
        org_ids = org_team_mappings.map(&:first)
        team_ids = org_team_mappings.map(&:last)
        enterprise_team.business&.add_users_to_organizations(user_ids, org_ids, actor: actor, caller_type: :enterprise_team, team_ids: team_ids)
      end

      org_ability_ids_to_remove = []

      mappings.each do |mapping|
        # TODO: revisit locking strategy later if applicable per resource; should be idempotent as designed
        with_write do # TODO: https://github.com/github/Identity-Teams/issues/136ss
          begin
            reconcile(enterprise_team: enterprise_team, mapping: mapping, org_ability_ids_to_remove: org_ability_ids_to_remove, out_of_sync_time: out_of_sync_time)
          rescue => ex # rubocop:disable Lint/GenericRescue
            mapping.reload
            log_message = if mapping.enterprise_team.nil?
              "Aborting enterprise_team_organization_reconciliation_runner_job due to missing enterprise team"
            else
              "Failed while reconciling mapping in enterprise_team_organization_reconciliation_runner_job"
            end
            GitHub.logger.error(
              "info.message" => log_message,
              "gh.enterprise_team.organization_mapping.id" => mapping.id,
              "gh.enterprise_team.id" => mapping.enterprise_team_id,
              "gh.organization.id" => mapping.organization_id,
              "gh.team.id" => mapping.team_id,
              :exception => ex
            )

            # We want to abort the job completely if the enterprise team no longer exists
            return if mapping.enterprise_team.nil?
            update_status(mapping: mapping, status: "failed", out_of_sync_time: out_of_sync_time)
            raise ex
          end
        end
      end

      if org_ability_ids_to_remove.any?
        with_write do
          GitHub.logger.info(
            "info.message" => "Removing #{org_ability_ids_to_remove.size} org members in batches",
            "gh.enterprise_team.id" => enterprise_team.id
          )
          enterprise_team.business&.remove_abilities_from_business(org_ability_ids_to_remove, actor: actor)
          GitHub.logger.info(
            "info.message" => "Removed #{org_ability_ids_to_remove.size} org members in batches",
            "gh.enterprise_team.id" => enterprise_team.id
          )
        end
      end

      unless enterprise_team.sync_to_organizations?
        with_write do
          GitHub.logger.info(
            "info.message" => "Destroying enterprise_team_organization_mappings",
            "gh.enterprise_team.id" => enterprise_team.id,
          )
          EnterpriseTeamOrganizationMapping.transaction do
            EnterpriseTeamOrganizationMapping.destroy(mappings.map(&:id))

            if enterprise_team.soft_deleted? && !enterprise_team.enterprise_team_organization_mappings.lock.exists?
              GitHub.logger.info(
                "info.message" => "Destroying enterprise_team",
                "gh.enterprise_team.id" => enterprise_team.id,
              )
              enterprise_team.destroy!
            end
          end
        end
      end

      if @updated_users&.any?
        User.where(id: @updated_users.flatten.uniq).each { |u| u.synchronize_search_index }
      end
    end
  end

  sig { override.returns(T::Array[T.class_of(ApplicationJob)]) }
  def fanout_jobs
    [
      RemoveOrgMemberJob,
      RemoveOrgMemberRepositoryStarsJob,
      RemoveOrgMemberWatchedRepositoriesJob,
      RemoveOrgMemberIssueAssignmentsJob,
      RevokeOrgMembershipAbilitiesJob,
      DeliverHookEventJob,
      AddToSearchIndexJob
    ]
  end

  private

  sig { returns(User) }
  memoize def actor
    @actor ||= T.let((User.find_by(id: GitHub.context[:actor_id]) || User.ghost), T.nilable(User))
  end

  # This method is defined only to be stubbed in unit test for a very specific edge case.
  sig { params(ids: T::Array[Integer]).returns(T::Array[User]) }
  def users_to_add(ids)
    User.where(id: ids).to_a
  end

  sig { params(enterprise_team: EnterpriseTeam, mapping: EnterpriseTeamOrganizationMapping, org_ability_ids_to_remove: T::Array[Integer], out_of_sync_time: Time).void }
  def reconcile(enterprise_team:, mapping:, org_ability_ids_to_remove:, out_of_sync_time:)
    GitHub.logger.info(
      "info.message" => "Reconciling team in enterprise_team_organization_reconciliation_runner_job",
      "gh.enterprise_team.organization_mapping.id" => mapping.id,
      "gh.enterprise_team.id" => mapping.enterprise_team_id,
      "gh.organization.id" => mapping.organization_id
    )

    if mapping.team.nil?
      GitHub.logger.info(
        "info.message" => "Skipping reconciliation for nil organization team in enterprise_team_organization_reconciliation_runner_job",
        "gh.enterprise_team.organization_mapping.id" => mapping.id,
        "gh.enterprise_team.id" => enterprise_team.id,
        "gh.organization.id" => mapping.organization_id
      )
      return
    end
    org_team = T.must(mapping.team)

    # Cache member lists
    enterprise_team_member_ids = enterprise_team.member_user_ids
    org_team_member_ids = org_team.members.pluck(:id)

    if enterprise_team.sync_to_organizations?
      to_add = enterprise_team_member_ids - org_team_member_ids
      to_remove = org_team_member_ids - enterprise_team_member_ids
    else
      GitHub.logger.info(
        "info.message" => "Sync is disabled, removing all org team members in enterprise_team_organization_reconciliation_runner_job",
        "gh.enterprise_team.organization_mapping.id" => mapping.id,
        "gh.enterprise_team.id" => enterprise_team.id,
        "gh.organization.id" => mapping.organization_id,
      )
      to_add = []
      to_remove = enterprise_team_member_ids & org_team_member_ids
    end

    GitHub.logger.info(
      "info.message" => "Computed to_add and to_remove in enterprise_team_organization_reconciliation_runner_job",
      "gh.enterprise_team.organization_mapping.id" => mapping.id,
      "gh.enterprise_team.id" => enterprise_team.id,
      "gh.organization.id" => mapping.organization_id,
      "gh.enterprise_team.member_ids.count" => enterprise_team_member_ids.size,
      "gh.enterprise_team.to_add_count" => to_add.size,
      "gh.enterprise_team.to_remove_count" => to_remove.size
    )

    # If we're adding more members than the max sync members, we should not add any members. We can allow removal
    unless enterprise_team.can_sync_to_organizations_member_check?
      GitHub.logger.error(
        "info.message" => "Aborting addition of new members in enterprise_team_organization_reconciliation_runner_job due to exceeding max sync members",
        "gh.enterprise_team.organization_mapping.id" => mapping.id,
        "gh.enterprise_team.id" => enterprise_team.id,
        "gh.organization.id" => mapping.organization_id,
        "gh.team.id" => org_team.id
      )
      abort_add = true
      to_add = []
    end

    @updated_users.push(to_add) if @updated_users && to_add.any?

    users_to_add = users_to_add(to_add)
    user_to_add_ids = to_add
    if to_add.size > users_to_add.size
      # some users were not found, were they deleted? part of https://github.com/github/Identity-Teams/issues/1093
      # Could not find evidence in audit log. Let's alert on it with more logging if it happens again.
      # Filter users_to_add_ids so they don't generate nil values after the zip call, which in turn would
      # Make the failed add status report string to raise a nil exception.
      # Another reason to filter here is that the nil would offset the index of the add statuses array and user id being reported
      # as having a nil status would not be the correct userid.
      user_to_add_ids = users_to_add.map(&:id)
      to_add_not_found = to_add - user_to_add_ids
      GitHub.logger.warn(
        "info.message" => "Some users to add to enterprise team were not found",
        "gh.enterprise_team.organization_mapping.id" => mapping.id,
        "gh.enterprise_team.id" => enterprise_team.id,
        "gh.organization.id" => mapping.organization_id,
        "gh.team.id" => org_team.id,
        "gh.user_ids" => to_add_not_found
      )
      GitHub.dogstats.increment(USER_NOT_FOUND_METRIC, tags: ["enterprise_team_id:#{enterprise_team.id}"])
    end

    add_member_statuses = org_team.bulk_add_members_with_failover(users_to_add, caller_type: :enterprise_team, send_notification: false, skip_user_synchronize_index: true) || []
    add_member_statuses = user_to_add_ids.zip(add_member_statuses)

    users_to_remove = User.where(id: to_remove)
    # TODO: Consolidate once we fully support SCIM groups in the bulk method https://github.com/github/Identity-Teams/issues/1483
    if EnterpriseTeam.enabled_for_organizations?(business: enterprise_team.business) &&
      enterprise_team.direct_memberships_enabled?
      org_team.bulk_remove_members(
        users: users_to_remove,
        caller_type: :enterprise_team,
        force: true,
        send_notification: false,
      )
    else
      users_to_remove.each do |user|
        org_team.remove_member(user, caller_type: :enterprise_team, force: true, send_notification: false)
      end
    end
    user_ids_to_remove_from_orgs = destroy_organization_membership_entries(users: users_to_remove, org_team: org_team)

    if user_ids_to_remove_from_orgs.any?
      org_ability_ids_to_remove.concat(Ability.where(
        actor_type: "User",
        actor_id: user_ids_to_remove_from_orgs,
        subject_type: "Organization",
        subject_id: mapping.organization_id,
      ).pluck(:id))
      GitHub.logger.info(
        "info.message" => "Added #{org_ability_ids_to_remove.size} org abilities to remove in batch for later",
        "gh.enterprise_team.organization_mapping.id" => mapping.id,
        "gh.enterprise_team.id" => enterprise_team.id,
        "gh.organization.id" => mapping.organization_id,
        "gh.team.id" => org_team.id
      )
    end

    failed_to_add = to_add - org_team.members.where(id: to_add).pluck(:id)
    failed_to_remove = org_team.members.where(id: to_remove).pluck(:id)
    if failed_to_add.empty? && failed_to_remove.empty? && !abort_add
      update_status(mapping: mapping, status: "synced", out_of_sync_time: out_of_sync_time)

      GitHub.logger.info(
        "info.message" => "Successfully reconciled team in enterprise_team_organization_reconciliation_runner_job",
        "gh.enterprise_team.organization_mapping.id" => mapping.id,
        "gh.enterprise_team.id" => enterprise_team.id,
        "gh.organization.id" => mapping.organization_id,
        "gh.team.id" => org_team.id
      )
    else
      update_status(mapping: mapping, status: "partial", out_of_sync_time: out_of_sync_time)

      log_message = "Only partially reconciled team in enterprise_team_organization_reconciliation_runner_job."
      unless failed_to_remove.empty?
        log_message += "\nThese users were not removed from the org team: #{failed_to_remove.join(', ')}"
      end
      unless add_member_statuses.empty?
        failed_statuses = add_member_statuses.select { |_, status| status&.status != :success }
        log_message += "\nThese users were not added to the org team:" unless failed_statuses.count == 0
        failed_statuses.each do |user_id, status|
          # By tracing bulk_add_members_with_failover and what we do with the return value,
          # status should never be nil here. But we definitely encountered nil in production:
          # https://splunk.githubapp.com/en-US/app/gh_reference_app/search?earliest=1712779200&latest=1712784993&q=search%20index%3Dprod-exceptions%20job%3D%22EnterpriseTeamOrganizationReconciliationJob%22%20class%3D%22undefined%20method%20%60status%27%20for%20nil%22&display.page.search.mode=smart&dispatch.sample_ratio=1&workload_pool=Standard&sid=1713397045.127646_298589E4-13B4-4DF5-B9F5-79D50DC5251B
          # Only way it could happen is if `User.where(id: to_add).to_a` returns a smaller array of users than to_add
          # Which would mean a user was deleted during the job run (between to_add = and the team.bulk_add).
          # We do not have evidence it actually happened even after looking at audit log.
          # There is now a patch to handle zip not generating nil values, but adding another check here for safety
          # in case the nil is generated elsewhere. Let's alert on it with more logging if it happens again.
          # If we encounter a nil status, then user_id might actually not match and be all offset in the array.
          # There is no way to fix that as team.bulk returns an unindexed array of statuses.
          # Pretty sure team.bulk_add never returns any nil value though and that User.where returning a smaller array is the reason we were hitting this.
          log_message += "\n#{user_id}: #{status&.status || "unknown status"}"
          GitHub.dogstats.increment(ADD_STATUS_NOT_FOUND_METRIC, tags: ["enterprise_team_id:#{enterprise_team.id}"]) if status.nil?
        end
      end

      GitHub.logger.info(
        "info.message" => log_message,
        "gh.enterprise_team.organization_mapping.id" => mapping.id,
        "gh.enterprise_team.id" => enterprise_team.id,
        "gh.organization.id" => mapping.organization_id,
        "gh.team.id" => org_team.id
      )
    end
  end

  sig { params(mapping: EnterpriseTeamOrganizationMapping, status: String, out_of_sync_time: Time).void }
  def update_status(mapping:, status:, out_of_sync_time:)
    time = Time.zone.now
    mapping.status = status
    mapping.synced_at = time
    mapping.save!

    duration_ms = (time - out_of_sync_time) * 1000
    GitHub.dogstats.distribution("enterprise_team.org_sync.latency", duration_ms, tags: ["id:#{mapping.id}"])
    GitHub.logger.info(
      "info.message" => "enterprise_team.org_sync.latency",
      "gh.enterprise_team.organization_mapping.id" => mapping.id,
      "gh.enterprise_team.id" => mapping.enterprise_team_id,
      "gh.organization.id" => mapping.organization_id,
      "gh.team.id" => mapping.team_id,
      "gh.duration_ms" => duration_ms
    )
  end

  sig { returns(GitHub::Restraint) }
  private def restraint
    @restraint ||= T.let(GitHub::Restraint.new, T.nilable(GitHub::Restraint))
  end

  # Attempts to acquires a lock for the given enterprise_team_id and team_id combo, which prevents multiple runners
  # accessing the same mapping resource concurrently
  # TODO: determine if we even need this? It _should_ be idempotent https://github.com/github/Identity-Teams/issues/1454
  sig { params(enterprise_team_id: Integer, team_id: Integer, block: T.proc.void).void }
  def acquire_team_lock!(enterprise_team_id, team_id, &block)
    restraint_key = "#{LOCK_KEY}#{enterprise_team_id}-#{team_id}"
    restraint.lock!(restraint_key, MAX_CONCURRENT_JOBS, RESTRAINT_LOCK_TTL) do
      block.call
    end
  end

  # Attempts to acquire a concurrency restraint lock for the job family, which limits the max number of jobs running
  # simultaneously (depending on ghe-config value)
  sig { params(enterprise_team: EnterpriseTeam, block: T.proc.void).void }
  def acquire_global_job_lock!(enterprise_team:, &block)
    restraint_key = "enterprise_team_organization_reconciliation_runner_job-global_limit-#{enterprise_team.business_id}"
    restraint.lock!(restraint_key, GitHub.max_concurrent_et_org_reconciliation_runners, RESTRAINT_LOCK_TTL) do
      block.call
    end
  end

  # Cleanup the organization membership entries for the Enterprise Team users that are being removed from the team
  sig { params(users: T.any(ActiveRecord::Relation, T::Array[User]), org_team: Team).returns(T::Array[Integer]) }
  private def destroy_organization_membership_entries(users:, org_team:)
    user_ids_to_remove_from_orgs = []

    org_membership_entries = OrganizationMembershipEntry.where(
      adder_type: :enterprise_team,
      user: users,
      organization_id: org_team.organization&.id
    )

    # Group entries by user and get their IDs
    single_entry_ids = []
    multiple_entry_ids = []
    org_membership_entries.group_by(&:user_id).each do |_, entries|
      if entries.count > 1
        multiple_entry_ids.concat(entries.map(&:id))
      else
        single_entry_ids.concat(entries.map(&:id))
      end
    end

    # These users have memberships through multiple ETs - just remove immediate team related record and don't remove
    # the user from the org completely
    multiple_entries = OrganizationMembershipEntry.where(id: multiple_entry_ids, adder_id: org_team.id)
    multiple_entries.destroy_all

    # Otherwise we can take them out completely
    single_entries = OrganizationMembershipEntry.where(id: single_entry_ids)
    single_entries_user_ids = single_entries.map(&:user_id)
    single_entries.destroy_all
    admin_membership_entries = OrganizationMembershipEntry.where(
      adder_type: :admin,
      user_id: single_entries_user_ids,
      organization_id: org_team.organization&.id
    )

    # Find user IDs that are in single_entries_user_ids but don't have an admin membership entry
    user_ids_to_remove_from_orgs = single_entries_user_ids - admin_membership_entries.pluck(:user_id)

    # cleanup - we only generate :admin OMEs for GHEC users in an ET so we destroy them when that lifecycle is completed
    admin_membership_entries.destroy_all unless org_team.organization&.scim_managed_enterprise?

    user_ids_to_remove_from_orgs
  end
end
