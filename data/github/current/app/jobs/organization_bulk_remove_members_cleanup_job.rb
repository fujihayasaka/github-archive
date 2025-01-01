# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: strict
# frozen_string_literal: true

# This job is to be called after revoking abilities from users. It performs the cleanup of non-ability related data
# for the users that were removed from the business.
class OrganizationBulkRemoveMembersCleanupJob < ApplicationJob
  include GitHub::Memoizer

  queue_as :organization_bulk_remove_members_cleanup

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  LOCK_TTL = T.let(10.minutes, Integer)
  retry_on GitHub::Restraint::UnableToLock, wait: LOCK_TTL, attempts: :unlimited, jitter: 0.3

  # The global lock ensures that only a certain number of these jobs can run at a single time.
  GLOBAL_LOCK_KEY = T.let("organization_bulk_remove_members_cleanup_job", String)
  GLOBAL_LOCK_MAX_CONCURRENT_JOBS = T.let(3, Integer)

  # The local lock ensures that only one job can run at a single time for the same user and organization IDs.
  LOCAL_LOCK_KEY_TEMPLATE = T.let("organization_bulk_remove_members_cleanup_job_operation_%<operation_id>s_users_%<user_ids>s_orgs_%<organization_ids>s", String)
  LOCAL_LOCK_MAX_CONCURRENT_JOBS = T.let(1, Integer)

  JOB_RECORD_BATCH_SIZE = 30
  WRITE_BATCH_SIZE = 100
  READ_REPO_BATCH_SIZE = 1000

  sig { returns(T.nilable(String)) }
  attr_reader :operation_id

  sig { returns(T.nilable(T::Array[Integer])) }
  attr_reader :user_ids

  sig { returns(T.nilable(T::Array[Integer])) }
  attr_reader :organization_ids

  sig { returns(T.nilable(T::Boolean)) }
  attr_reader :has_next_organization_ids_page

  sig { returns(T.nilable(User)) }
  attr_reader :actor

  sig { returns(T.nilable(String)) }
  attr_reader :reason

  sig do
    params(
      operation_id: T.nilable(String),
      organization_ids: T::Array[Integer],
      user_ids: T::Array[Integer],
      remove_direct_repo_access: T::Boolean,
      remove_team_membership: T::Boolean,
      remove_user_roles: T::Boolean,
      organization_ids_page: Integer,
      user_ids_page: Integer,
      reason: T.nilable(String),
      actor: T.nilable(User),
      business_team_operation: T::Boolean,
    ).void
  end
  def perform(
    operation_id: nil,
    organization_ids: [],
    user_ids: [],
    remove_direct_repo_access: false,
    remove_team_membership: true,
    remove_user_roles: true,
    organization_ids_page: 1,
    user_ids_page: 1,
    reason: nil,
    actor: nil,
    business_team_operation: false
  )
    operation_id ||= SecureRandom.uuid
    @operation_id = T.let(operation_id, T.nilable(String))
    @business_team_operation = T.let(business_team_operation, T.nilable(T::Boolean))

    all_user_ids = T.let(user_ids.compact, T.nilable(T::Array[Integer]))
    all_organization_ids = T.let(organization_ids.compact, T.nilable(T::Array[Integer]))
    return if T.must(all_user_ids).empty? || T.must(all_organization_ids).empty?

    @reason = T.let(reason, T.nilable(String))
    @actor = T.let(actor, T.nilable(User))
    log_timing("organization_bulk_remove_members_cleanup_job.perform_slice",
      "gh.operation_id": operation_id,
      "gh.organization_ids.page": organization_ids_page,
      "gh.organization_ids.size": organization_ids.size,
      "gh.user_ids.page": user_ids_page,
      "gh.user_ids.size": user_ids.size,
    ) do

      slice_organization_ids = organization_ids.paginate(page: organization_ids_page, per_page: JOB_RECORD_BATCH_SIZE)
      slice_user_ids = user_ids.paginate(page: user_ids_page, per_page: JOB_RECORD_BATCH_SIZE)

      @user_ids = T.let(slice_user_ids, T.nilable(T::Array[Integer]))
      @organization_ids = T.let(slice_organization_ids, T.nilable(T::Array[Integer]))
      @has_next_organization_ids_page = T.let(slice_organization_ids.next_page.present?, T.nilable(T::Boolean))

      max_jobs = GLOBAL_LOCK_MAX_CONCURRENT_JOBS
      if @organization_ids && business_team_operation
        business = Organization.find_by(id: @organization_ids.first)&.business
        if business&.feature_flag_enabled?(:org_bulk_member_cleanup_job_use_configurable_max_concurrent_value, default: false)
          max_jobs = GitHub.business_team_org_remove_member_job_limit
        end
      end

      restraint.lock!(GLOBAL_LOCK_KEY, max_jobs, LOCK_TTL) do
        begin
          restraint.lock!(local_lock_key(operation_id:, user_ids:, organization_ids:), LOCAL_LOCK_MAX_CONCURRENT_JOBS, LOCK_TTL) do
            perform_slice(
              organization_ids: slice_organization_ids,
              user_ids: slice_user_ids,
              remove_direct_repo_access: remove_direct_repo_access,
              remove_team_membership: remove_team_membership,
              remove_user_roles: remove_user_roles,
              reason: reason,
              actor: actor
            )
          end
        rescue GitHub::Restraint::UnableToLock => e
          GitHub.logger.info("Duplicate OrganizationBulkRemoveMembersCleanupJob run detected, exiting", {
            "gh.operation_id": operation_id,
            "gh.user_ids": slice_user_ids,
            "gh.organization_ids.page": organization_ids_page,
            "gh.organization_ids.size": organization_ids.size,
            "gh.user_ids.page": user_ids_page,
            "gh.user_ids.size": user_ids.size,
          })
          return
        end
      end

      if slice_user_ids.next_page != nil
        OrganizationBulkRemoveMembersCleanupJob.perform_later(
          operation_id: operation_id,
          organization_ids: organization_ids,
          user_ids: user_ids,
          remove_direct_repo_access: remove_direct_repo_access,
          remove_team_membership: remove_team_membership,
          remove_user_roles: remove_user_roles,
          organization_ids_page: organization_ids_page,
          user_ids_page: slice_user_ids.next_page,
          reason: reason,
          actor: actor
        )
      elsif slice_organization_ids.next_page != nil
        OrganizationBulkRemoveMembersCleanupJob.perform_later(
          operation_id: operation_id,
          organization_ids: organization_ids,
          user_ids: user_ids,
          remove_direct_repo_access: remove_direct_repo_access,
          remove_team_membership: remove_team_membership,
          remove_user_roles: remove_user_roles,
          organization_ids_page: slice_organization_ids.next_page,
          user_ids_page: 1,
          reason: reason,
          actor: actor
        )
      end
    end
  end

  private

  sig { params(operation_id: String, user_ids: T::Array[Integer], organization_ids: T::Array[Integer]).returns(String) }
  def local_lock_key(operation_id:, user_ids:, organization_ids:)
    Digest::SHA256.hexdigest(format(LOCAL_LOCK_KEY_TEMPLATE, operation_id:, user_ids: user_ids.join(","), organization_ids: organization_ids.join(",")))
  end

  sig { returns(GitHub::Restraint) }
  memoize def restraint
    GitHub::Restraint.new
  end

  sig do
    params(
      organization_ids: T::Array[Integer],
      user_ids: T::Array[Integer],
      remove_direct_repo_access: T::Boolean,
      remove_team_membership: T::Boolean,
      remove_user_roles: T::Boolean,
      reason: T.nilable(String),
      actor: T.nilable(User)
    ).void
  end
  def perform_slice(
    organization_ids: [],
    user_ids: [],
    remove_direct_repo_access: false,
    remove_team_membership: true,
    remove_user_roles: true,
    reason: nil,
    actor: nil
  )
    payloads = T.let([], T::Array[T::Hash[T.untyped, T.untyped]])

    # Loop through organizations, and cleanup multiple users at a time
    business = T.let(nil, T.nilable(Business))
    Organization.where(id: organization_ids).includes(:business).find_each(batch_size: WRITE_BATCH_SIZE) do |org|
      business = org.business
      return if business&.kill_switch_enabled?("OrganizationBulkRemoveMembersCleanupJob", feature_flag: :enterprise_teams_killswitch, log_fields: {
        "gh.business.id": business.id,
        "gh.organization.id": org.id
      })

      payloads = log_timing("organization_bulk_remove_members_cleanup_job.multi_user_single_org_cleanup",
          "gh.operation_id": operation_id,
          "gh.organization.id": org.id,
          "gh.business.id": business&.id,
          "gh.user_ids.size": user_ids.size,
        ) do
        multi_user_single_org_cleanup(org, remove_direct_repo_access:, remove_team_membership:, remove_user_roles:)
      end

      if EnterpriseTeam.enabled_for_organizations?(business: business)
        BackgroundInstrumentationJob.perform_later org, :remove_member, payloads
      end
    end

    # Loop through users, and cleanup multiple organizations at a time
    user_ids.each do |user_id|
      log_timing("organization_bulk_remove_members_cleanup_job.single_user_multi_org_cleanup",
        "gh.operation_id": operation_id,
        "gh.business.id": business&.id,
        "gh.user.id": user_id,
      ) do
        single_user_multi_org_cleanup(user_id)
      end
    end

    business&.update_license_usage unless has_next_organization_ids_page
  end

  sig { params(user_id: Integer).void }
  def single_user_multi_org_cleanup(user_id)
    # This job can run on org/user id combos that don't need any cleanup.
    # Remove any valid org ids before processing the rest.
    user = T.must(User.find_by(id: user_id))
    org_ids = T.must(organization_ids) - user.organization_ids
    return if org_ids.empty?

    # The bulk versions are slower when removing only a single org. In that case, we want to use the single version
    if org_ids.count > 1
      BulkRemoveOrgMemberWatchedRepositoriesJob.perform_later(user_id:, organization_ids: org_ids)
      BulkRemoveOrgMemberRepositoryStarsJob.perform_later(user_id:, organization_ids: org_ids)
      BulkRemoveOrgMemberForksJob.perform_later(user_id:, organization_ids: org_ids, send_email: false)
      DenyForkCollabStateForUserPullRequestsJob.perform_later(user_id: user_id, resource_id: nil, resource_class: "Organization", resource_ids: org_ids)
      BulkRemoveOrgMemberIssueAssignmentsJob.perform_later(user_id: user_id, organization_ids: org_ids)
    else
      legacy_job_options = { "organization_id" => org_ids.first, "user_id" => user_id }
      org = T.must(Organization.find_by(id: org_ids.first))
      RemoveOrgMemberWatchedRepositoriesJob.perform_later(legacy_job_options)
      RemoveOrgMemberRepositoryStarsJob.perform_later(legacy_job_options)
      RemoveOrgMemberForksJob.perform_later(legacy_job_options)
      DenyForkCollabStateForUserPullRequestsJob.perform_later(user_id: user_id, resource_id: org_ids.first, resource_class: "Organization")
      RemoveOrgMemberIssueAssignmentsJob.perform_later(org, user)
    end

    notify_repository_access_changed(user_id)

    unless has_next_organization_ids_page
      user.synchronize_search_index
    end
  end

  sig { params(org: Organization, remove_direct_repo_access: T::Boolean, remove_team_membership: T::Boolean, remove_user_roles: T::Boolean).returns(T::Array[T::Hash[T.untyped, T.untyped]]) }
  def multi_user_single_org_cleanup(org, remove_direct_repo_access: false, remove_team_membership: true, remove_user_roles: true)
    payloads = []

    cleanup_user_ids, collaborating_repos, moderators = log_timing(
      "organization_bulk_remove_members_cleanup_job.multi_user_single_org_cleanup.before_user_loop",
      "gh.operation_id": operation_id,
      "gh.business.id": org.business&.id,
      "gh.organization.id": org.id
    ) do
      # This job can run on org/user id combos that don't need any cleanup.
      # Remove any valid users before processing the rest.
      cleanup_user_ids = T.must(user_ids) - org.member_ids(actor_ids: user_ids)
      org.cancel_team_membership_requests_for(cleanup_user_ids)

      collaborating_repos = org.collaborating_repositories_for(cleanup_user_ids)
      moderators = org.moderators

      # Operations that are done per organization
      IntegrationInstallation.where(target_id: org.id).each do |installation|
        UpdateIntegrationInstallationRateLimitJob.perform_later(installation.id)
      end
      TradeControls::OrganizationComplianceCheckJob.perform_later(org.id, reason: :organization_admin)

      [cleanup_user_ids, collaborating_repos, moderators]
    end

    # Operations that cannot be done in bulk
    User.where(id: cleanup_user_ids).find_in_batches(batch_size: WRITE_BATCH_SIZE) do |user_group|
      org.business&.raise_if_kill_switch_enabled!("OrganizationBulkRemoveMembersCleanupJob",
        feature_flag: :enterprise_teams_killswitch,
        log_fields: { "gh.business.id": org.business&.id, "gh.organization.id": org.id }
      )
      log_timing("organization_bulk_remove_members_cleanup_job.multi_user_single_org_cleanup.user_group",
        "gh.operation_id": operation_id,
        "gh.business.id": org.business&.id,
        "gh.organization.id": org.id,
        "gh.user.ids.size": user_group.size,
      ) do
        org.conceal_members(user_group, skip_search_index: true)
        org.remove_direct_repo_access_for(user_group, collaborating_repos) if remove_direct_repo_access
        user_group.each do |user|
          if user
            MemberFeatureRequest.remove_all_member_requests(user, org)

            if org.has_linked_billing_contact_to_actor?(actor: user)
              org.unlink_billing_contact(actor: user)
            end

            user_has_direct_repo_access = collaborating_repos.key?(user.id)
            becomes_outside_collaborator = !remove_direct_repo_access && user_has_direct_repo_access
            org.remove_direct_project_access(user)
            org.remove_direct_project_next_access(user) unless becomes_outside_collaborator

            with_write { org.remove_user_email_setting_for_org(user) }

            with_write { org.moderation.remove_moderator(user, actor: nil, force: true) } if moderators.include?(user)

            with_write { Contribution.clear_caches_for_user(user, context: "organization_bulk_remove_members_cleanup_job") }

            user.destroy_org_restricted_user_status(org)

            if remove_team_membership
              org.teams_for(user).each do |team|
                with_write { team.remove_member(user, force: true, send_notification: false, queue_delete_jobs: false) }
              end
            end

            # Remove Organization UserRole assignments
            if remove_user_roles
              user_role_revoke_retry_count = 3
              begin
                with_write { Permissions::Granters::RoleGranter.new(actor: user, target: org).revoke_if_exists! }
              rescue ::Permissions::Granters::RoleGranter::GrantFailure => e
                # In practice revoke failures shouldn't happen.
                (user_role_revoke_retry_count -= 1) && retry if user_role_revoke_retry_count > 0
                raise # Re=raise the same error
              end
            end

            legacy_job_options = { "organization_id" => org.id, "user_id" => user.id }
            RemoveOrgMemberVulnerabilityManagementJob.perform_later(legacy_job_options)
            RevokeOrgAppsManagementGrantsJob.perform_later(org, user)

            packages = org.packages
            packages.each_slice(100) do |package_batch|
              RemoveOrgMemberPackageAccessV2Job.perform_later(user, package_batch) unless GitHub.enterprise?
            end

            payloads << instrument_removal(org, user)
          end
        end
      end
    end

    unless GitHub.single_business_environment?
      log_timing("organization_bulk_remove_members_cleanup_job.multi_user_single_org_cleanup.after_user_loop",
        "gh.operation_id": operation_id,
        "gh.business.id": org.business&.id,
        "gh.organization.id": org.id,
      ) do
        if org.saml_sso_enabled?
          ExternalIdentity.unlink_saml_identities(provider: org.saml_provider, user_ids: cleanup_user_ids)
        end

        if org.sponsors_listing.present?
          sponsors_listing_featured_item = org.sponsors_listing&.featured_users&.where(featureable_id: cleanup_user_ids)
          with_write { sponsors_listing_featured_item&.destroy_all }
        end
      end
    end

    payloads
  end

  sig { params(org: Organization, user: User).returns(T::Hash[T.untyped, T.untyped]) }
  def instrument_removal(org, user)
    instrument_options = {
      user: user,
      reason: reason,
      membership_types: ["direct_member"], # Limit to direct members for now. Tracked in https://github.com/github/meao/issues/2433
      actor: actor,
      business_team_operation: @business_team_operation
    }

    if GitHub.context[:hide_staff_user] && GitHub.guard_audit_log_staff_actor?
      instrument_options.merge!(GitHub.guarded_audit_log_staff_actor_entry(actor))
      # GlobalInstrumenter requires a real user
      instrument_options[:actor] = User.staff_user
    end

    if EnterpriseTeam.enabled_for_organizations?(business: org.business)
      instrument_options[:timestamp_override] = Time.current
    elsif !@business_team_operation
      org.instrument :remove_member, instrument_options
    end

    options = instrument_options.merge(org: org, action: :remove)
    GlobalInstrumenter.instrument "org.remove_member", options

    instrument_options
  end

  sig { params(user_id: Integer).void }
  def notify_repository_access_changed(user_id)
    user = T.must(User.find_by(id: user_id))
    repo_ids = inaccessible_org_repo_ids_for(user)

    GlobalInstrumenter.instrument(GlobalEvents::User::REPOSITORY_ACCESS_CHANGED, {
      user: user,
      repository_ids: repo_ids,
    })
  end

  sig { params(user: User).returns(T::Array[Integer]) }
  def inaccessible_org_repo_ids_for(user)
    all_orgs_private_repo_ids - repo_ids_visible_to_user(user, all_orgs_private_repo_ids)
  end

  sig { returns(T::Array[Integer]) }
  memoize def all_orgs_private_repo_ids
    Repository.where(organization_id: organization_ids).private_scope.pluck(:id)
  end

  sig { params(user: User, repo_ids: T::Array[Integer]).returns(T::Array[Integer]) }
  def repo_ids_visible_to_user(user, repo_ids)
    associated_repository_ids = []
    repo_ids.each_slice(READ_REPO_BATCH_SIZE).map do |group_ids|
      Repository.throttle do
        associated_ids = user.associated_repository_ids(repository_ids: group_ids)
        associated_repository_ids.concat(associated_ids).uniq!
      end
    end

    # Load all internal repositories for the user. This is only to exclude internal repos from being considered
    # accessible, so it doesn't matter if we load Rando Business internal IDs.
    associated_repository_ids |= user.internal_repositories.pluck(:id)
    associated_repository_ids
  end

  sig { params(operation: String, log_fields: T::Hash[String, T.untyped], block: T.proc.void).returns(T.untyped) }
  def log_timing(operation, log_fields, &block)
    GitHub.logger.info("#{operation}.start", log_fields)
    start = GitHub::Dogstats.monotonic_time
    block.call
  ensure
    duration_ms = (GitHub::Dogstats.monotonic_time - start) * 1000
    GitHub.logger.info("#{operation}.completed", log_fields.merge("gh.duration_ms": duration_ms))
  end
end
