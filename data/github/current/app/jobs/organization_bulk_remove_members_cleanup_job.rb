# typed: strict
# frozen_string_literal: true

# This job is to be called after revoking abilities from users. It performs the cleanup of non-ability related data
# for the users that were removed from the business.
class OrganizationBulkRemoveMembersCleanupJob < ApplicationJob
  include GitHub::Memoizer

  queue_as :organization_bulk_remove_members_cleanup

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  WRITE_BATCH_SIZE = 100
  READ_BATCH_SIZE = 1000

  sig { returns(T.nilable(T::Array[Integer])) }
  attr_reader :user_ids

  sig { returns(T.nilable(T::Array[Integer])) }
  attr_reader :organization_ids

  sig { returns(T.nilable(User)) }
  attr_reader :actor

  sig { returns(T.nilable(String)) }
  attr_reader :reason

  sig do
    params(
      organization_ids: T::Array[Integer],
      user_ids: T::Array[Integer],
      remove_direct_repo_access: T::Boolean,
      remove_team_membership: T::Boolean,
      reason: T.nilable(String),
      actor: T.nilable(User)
    ).void
  end
  def perform(
    organization_ids: [],
    user_ids: [],
    remove_direct_repo_access: false,
    remove_team_membership: true,
    reason: nil,
    actor: nil
  )
    @user_ids = T.let(user_ids.compact, T.nilable(T::Array[Integer]))
    @organization_ids = T.let(organization_ids.compact, T.nilable(T::Array[Integer]))
    return if T.must(@user_ids).empty? || T.must(@organization_ids).empty?

    @reason = T.let(reason, T.nilable(String))
    @actor = T.let(actor, T.nilable(User))

    payloads = T.let([], T::Array[T::Hash[T.untyped, T.untyped]])

    # Loop through organizations, and cleanup multiple users at a time
    Organization.where(id: organization_ids).find_each(batch_size: WRITE_BATCH_SIZE) do |org|
      payloads = multi_user_single_org_cleanup(org, remove_direct_repo_access:, remove_team_membership:)

      if EnterpriseTeam.enabled_for_organizations?(business: org.business)
        BackgroundInstrumentationJob.perform_later org, :remove_member, payloads
      end
    end

    # Loop through users, and cleanup multiple organizations at a time
    user_ids.each do |user_id|
      single_user_multi_org_cleanup(user_id)
    end
  end

  private

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
    user.synchronize_search_index
  end

  sig { params(org: Organization, remove_direct_repo_access: T::Boolean, remove_team_membership: T::Boolean).returns(T::Array[T::Hash[T.untyped, T.untyped]]) }
  def multi_user_single_org_cleanup(org, remove_direct_repo_access: false, remove_team_membership: true)
    payloads = []
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

    # Operations that cannot be done in bulk
    User.where(id: cleanup_user_ids).find_in_batches(batch_size: WRITE_BATCH_SIZE) do |user_group|
      org.conceal_members(user_group, skip_search_index: true)
      user_group.each do |user|
        if user
          MemberFeatureRequest.remove_all_member_requests(user, org)

          if user.has_trade_screening_record_linked_to_org?(organization: org)
            user.unlink_trade_screening_record_from_org(organization: org)
          end

          user_has_direct_repo_access = collaborating_repos.key?(user.id)
          becomes_outside_collaborator = !remove_direct_repo_access && user_has_direct_repo_access
          org.remove_direct_project_access(user)
          org.remove_direct_project_next_access(user) unless becomes_outside_collaborator

          with_write { org.remove_user_email_setting_for_org(user) }

          with_write { org.moderation.remove_moderator(user, actor: nil, force: true) } if moderators.include?(user)

          org.remove_direct_repo_access(user, collaborating_repos[user.id]) if remove_direct_repo_access && user_has_direct_repo_access
          with_write { Contribution.clear_caches_for_user(user, context: "organization_bulk_remove_members_cleanup_job") }

          user.destroy_org_restricted_user_status(org)

          if remove_team_membership
            org.teams_for(user).each do |team|
              with_write { team.remove_member(user, force: true, send_notification: false, queue_delete_jobs: false) }
            end
          end

          # Remove Organization UserRole assignments
          user_role_revoke_retry_count = 3
          begin
            with_write { Permissions::Granters::RoleGranter.new(actor: user, target: org).revoke_if_exists! }
          rescue ::Permissions::Granters::RoleGranter::GrantFailure => e
            # In practice revoke failures shouldn't happen.
            (user_role_revoke_retry_count -= 1) && retry if user_role_revoke_retry_count > 0
            raise # Re=raise the same error
          end

          legacy_job_options = { "organization_id" => org.id, "user_id" => user.id }
          RemoveOrgMemberVulnerabilityManagementJob.perform_later(legacy_job_options)
          RevokeOrgAppsManagementGrantsJob.perform_later(org, user)
          RemoveOrgMemberPackageAccessJob.perform_later(org, user) unless GitHub.enterprise?

          payloads << instrument_removal(org, user)
        end
      end
    end

    unless GitHub.single_business_environment?
      if org.saml_sso_enabled?
        ExternalIdentity.unlink_saml_identities(provider: org.saml_provider, user_ids: cleanup_user_ids)
      end

      if org.sponsors_listing.present?
        sponsors_listing_featured_item = org.sponsors_listing&.featured_users&.where(featureable_id: cleanup_user_ids)
        with_write { sponsors_listing_featured_item&.destroy_all }
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
    }

    if GitHub.context[:hide_staff_user] && GitHub.guard_audit_log_staff_actor?
      instrument_options.merge!(GitHub.guarded_audit_log_staff_actor_entry(actor))
      # GlobalInstrumenter requires a real user
      instrument_options[:actor] = User.staff_user
    end

    if EnterpriseTeam.enabled_for_organizations?(business: org.business)
      instrument_options[:timestamp_override] = Time.current
    else
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
    repo_ids.each_slice(READ_BATCH_SIZE).map do |group_ids|
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
end
