# typed: true
# frozen_string_literal: true

class RemoveOrganizationMembersCleanupBusinessOrchestration < BusinessOrchestration
  include GitHub::Memoizer

  job_start

  step :remove_direct_repo_access do
    return unless data[:remove_direct_repo_access]
    repository_advisories = []
    in_batches do |user_ids, organization_ids|
      return :skipped if kill_switch_enabled?

      affected_repo_ids = []
      instrumentation_payloads = []

      repository_ids = Repository.where(owner_id: organization_ids).pluck(:id)
      repository_ids.each_slice(READ_REPO_BATCH_SIZE).map do |repo_ids|
        revoked_ability_ids = []
        abilities = Ability.where(
          actor_type: "User",
          actor_id: user_ids,
          subject_type: "Repository",
          subject_id: repo_ids,
          priority: Ability.priorities[:direct],
        ).pluck(:id, :actor_id, :subject_id)
        next if abilities.none?
        ability_ids = abilities.map(&:first)
        affected_repo_ids.concat(abilities.map(&:last))

        # Ability#revoke_remaining_role!
        with_write { Permissions::Granters::RoleGranter.bulk_revoke(actor_type: "User", actor_ids: user_ids, target_type: "Repository", target_ids: repo_ids) }
        # Ability.bulk_revoke
        revoked_ability_ids += ability_ids

        # vulnerability_manager.bulk_revoke
        vulnerability_manager_ability_ids = Ability.where(
          actor_type: "User",
          actor_id: user_ids,
          subject_type: "Repository:VulnerabilityManagement",
          subject_id: repo_ids,
          priority: Ability.priorities[:direct],
        ).pluck(:id)
        revoked_ability_ids += vulnerability_manager_ability_ids

        # Repository::AdvisoryAbilityManager.revoke in revoke_repository_advisory_abilities step
        advisories = RepositoryAdvisory.where(repository_id: repo_ids).all
        repository_advisories.concat(Ability.where(
          actor_type: "User",
          actor_id: user_ids,
          subject_type: "RepositoryAdvisory",
          subject_id: advisories.pluck(:id),
          priority: Ability.priorities[:direct],
        ).pluck(:subject_id, :actor_id).map do |adv|
          [T.must(advisories.find { |a| a.id == adv.first }).repository_id, adv.last]
        end)

        # ProtectedBranch::AbilityRepositoryManager.revoke
        protected_branch_ids = ProtectedBranch.where(repository_id: repo_ids).pluck(:id)
        revoked_ability_ids += Ability.where(
          actor_type: "User",
          actor_id: user_ids,
          subject_type: "ProtectedBranch",
          subject_id: protected_branch_ids,
          priority: Ability.priorities[:direct],
        ).pluck(:id)

        # Ability.bulk_revoke
        revoked_ability_ids.each_slice(100) do |ability_id_slice|
          instrumentation_payloads.concat(
            Ability.where(id: ability_id_slice).map { |a| a.instrumentation_payload(:revoke) }
          )
          with_write { Ability.where(id: ability_id_slice).delete_all }
          with_write { Ability.delete_dependent_abilities_for(ability_id_slice) }
        end

        all_users = User.where(id: abilities.map { |a| a[1] }).all
        # Repository.disassociate_member instrumentation
        Repository.where(id: abilities.map(&:last)).each do |repo|
          repo_user_ids = abilities.select { |a| a.last == repo.id }.map { |a| a[1] }
          users = all_users.select { |u| repo_user_ids.include?(u.id) }
          instrumentation_payloads.concat(
            users.map { |user| repo.instrumentation_payload :remove_member, user: user, actor: actor }
          )
          users.each do |user|
            GlobalInstrumenter.instrument("repo.remove_member", {
              user: user,
              actor: actor,
              repo: repo,
              action: :remove,
            })
          end
        end

        all_users.each do |user|
          repository_ids = abilities.select { |a| a[1] == user.id }.map(&:last)
          GlobalInstrumenter.instrument(GlobalEvents::User::REPOSITORY_ACCESS_CHANGED, {
            user: user,
            repository_ids: repository_ids,
          })
        end
      end

      instrument_events(instrumentation_payloads)

      # schedule_package_access_job
      Repository.batched_scope(:id, values: affected_repo_ids.uniq).each do |repo|
        repo.schedule_package_access_job
      end

      data[:repository_advisories] = repository_advisories
    end
  end

  step :remove_organization_collaborators do
    return if GitHub.single_business_environment?
    in_batches do |user_ids, organization_ids|
      with_write { OrganizationCollaborator.where(organization_id: organization_ids, user_id: user_ids).destroy_all }
    end
  end

  step :revoke_repository_advisory_abilities do
    advisory_data = (data[:repository_advisories] || []).uniq
    repositories = Repository.where(id: advisory_data.map(&:first).uniq).index_by(&:id)
    users = User.where(id: advisory_data.map(&:last).uniq).index_by(&:id)
    advisory_data.each do |advisory_and_user|
      with_write { Repository::AdvisoryAbilityManager.revoke(users[advisory_and_user.last], repository: repositories[advisory_and_user.first], actor: actor) }
    end
  end

  step :remove_direct_project_access do
    instrumentation_payloads = []
    in_batches do |user_ids, organization_ids|
      return :skipped if kill_switch_enabled?
      projects = Project.where(owner_type: "Organization", owner_id: organization_ids).all
      project_ids = projects.pluck(:id)
      next if project_ids.none?
      project_abilities = Ability.distinct.where(
        actor_type: "User",
        actor_id: user_ids,
        subject_type: "Project",
        subject_id: project_ids,
        priority: Ability.priorities[:direct],
      ).pluck(:actor_id, :action, :subject_id)
      next if project_abilities.none?
      with_write { Ability.bulk_revoke(actor_type: "User", actor_ids: user_ids, subject_type: "Project", subject_ids: project_ids, background: false) }
      users_by_id = User.where(id: project_abilities.map(&:first)).index_by(&:id)
      projects.each do |project|
        project_users = project_abilities.select { |a| a.last == project.id }
        instrumentation_payloads.concat(
          project_users.map { |ability| project.instrumentation_payload :update_user_permission, user: users_by_id[ability.first], changes: { permission: nil, old_permission: ability[1] } }
        )
      end
    end
    instrument_events(instrumentation_payloads)
  end

  step :remove_direct_project_next_access do
    if data[:remove_direct_repo_access]
      in_batches do |user_ids, organization_ids|
        return :skipped if kill_switch_enabled?
        project_ids = MemexProject.where(owner_type: "Organization", owner_id: organization_ids).pluck(:id)
        with_write { Permissions::Granters::RoleGranter.bulk_revoke(actor_type: "User", actor_ids: user_ids, target_type: "MemexProject", target_ids: project_ids) }
      end
    else
      organizations.each do |org|
        return :skipped if kill_switch_enabled?
        user_ids_to_remove = users.filter_map do |user|
          next if org.user_collaborates_on_any_repositories?(user.id)
          user.id
        end

        with_write { BulkRemoveOrgMemberProjectsNextAccessJob.perform_now(org, user_ids_to_remove) }
      end
    end
  end

  step :remove_team_membership do
    if data[:remove_team_membership]
      organizations.each do |org|
        return :skipped if kill_switch_enabled?
        users.each do |user|
          org.teams_for(user).each do |team|
            # TODO: Use Team#bulk_remove_members instead
            with_write { team.remove_member(user, force: true, send_notification: false, queue_delete_jobs: false) }
          end
        end
      end
    end
  end

  step :conceal_members do
    in_batches do |user_ids, organization_ids|
      with_write { Organization.conceal_members(org_ids: organization_ids, user_ids: user_ids) }
    end
  end

  step :update_license_usage do
    return if GitHub.single_business_environment? || data[:skip_license_usage_update] == true

    with_write { business&.update_license_usage }
  end

  step :remove_org_member_jobs do
    org_ids = T.must(organization_ids)
    org = nil
    org = T.must(Organization.find_by(id: org_ids.first)) if org_ids.size == 1
    users.each do |user|
      user_id = user.id
      if org_ids.count > 1
        BulkRemoveOrgMemberWatchedRepositoriesJob.perform_later(user_id:, organization_ids: org_ids)
        BulkRemoveOrgMemberRepositoryStarsJob.perform_later(user_id:, organization_ids: org_ids)
        BulkRemoveOrgMemberForksJob.perform_later(user_id:, organization_ids: org_ids, send_email: false)
        DenyForkCollabStateForUserPullRequestsJob.perform_later(user_id:, resource_id: nil, resource_class: "Organization", resource_ids: org_ids)
        BulkRemoveOrgMemberIssueAssignmentsJob.perform_later(user_id:, organization_ids: org_ids)
      else
        legacy_job_options = { "organization_id" => org_ids.first, "user_id" => user_id }
        RemoveOrgMemberWatchedRepositoriesJob.perform_later(legacy_job_options)
        RemoveOrgMemberRepositoryStarsJob.perform_later(legacy_job_options)
        RemoveOrgMemberForksJob.perform_later(legacy_job_options)
        DenyForkCollabStateForUserPullRequestsJob.perform_later(user_id:, resource_id: org_ids.first, resource_class: "Organization")
        RemoveOrgMemberIssueAssignmentsJob.perform_later(org, user)
      end
    end
  end

  step :synchronize_user_search_index do
    users.each do |user|
      user.synchronize_search_index
    end
  end

  step :cancel_team_membership_requests do
    organizations.each do |org|
      cleanup_user_ids = T.must(user_ids) - org.member_ids(actor_ids: T.must(user_ids))
      with_write { org.cancel_team_membership_requests_for(cleanup_user_ids) }
    end
  end

  step :update_integration_installation_rate_limits do
    organizations.each do |org|
      IntegrationInstallation.where(target: org).pluck(:id).each do |installation_id|
        UpdateIntegrationInstallationRateLimitJob.perform_later(installation_id)
      end
    end
  end

  step :trade_controls_organization_compliance_check do
    organizations.each do |org|
      TradeControls::OrganizationComplianceCheckJob.perform_later(org.id, reason: :organization_admin)
    end
  end

  step :remove_all_member_requests do
    in_batches(orgs: true) do |user_ids, organization_ids|
      request_ids = MemberFeatureRequest.where(requester_id: user_ids, request_entity_type: "User", request_entity_id: organization_ids).pluck(:id)
      next unless request_ids.any?
      MemberFeatureRequest.transaction do
        with_write { MemberFeatureRequest.where(id: request_ids).delete_all }
      end
    end
  end

  step :unlink_billing_contacts do
    organizations.each do |org|
      users.each do |user|
        if org.has_linked_billing_contact_to_actor?(actor: user)
          with_write { org.unlink_billing_contact(actor: user) }
        end
      end
    end
  end

  step :remove_moderators do
    instrumentation_payloads = []
    in_batches do |user_ids, organization_ids|
      abilities = Ability.where(
        actor_id: user_ids,
        actor_type: "User",
        subject_id: organization_ids,
        subject_type: "Organization::Moderation",
        priority: Ability.priorities[:direct],
      ).pluck(:actor_id, :subject_id)
      next if abilities.none?
      users = User.where(id: abilities.map(&:first)).all
      organizations = Organization.where(id: abilities.map(&:last)).all
      organizations.each do |org|
        moderation = Organization::Moderation.new(org)
        org_users = Set.new(abilities.select { |a| a.last == org.id }.map(&:first))
        instrumentation_payloads.concat(users.select { |u| org_users.include?(u.id) }.map { |user| moderation.instrumentation_payload_for(action: :remove, moderator: user, actor: actor) })
      end
      with_write { Ability.bulk_revoke(actor_type: "User", actor_ids: user_ids, subject_type: "Organization::Moderation", subject_ids: organization_ids) }
    end

    instrument_events(instrumentation_payloads)
  end

  step :clear_contribution_caches do
    users = self.users.to_a
    return if users.none?
    with_write { Contribution.bulk_clear_caches_for_users(users, context: "RemoveOrganizationMembersCleanupBusinessOrchestration") }
  end

  step :destroy_org_restricted_user_status do
    in_batches(orgs: true) do |user_ids, organization_ids|
      status_ids = UserStatus.where(user_id: user_ids, organization_id: organization_ids).pluck(:id)
      next unless status_ids.any?
      with_write { UserStatus.where(id: status_ids).destroy_all }
    end
  end

  step :remove_user_roles, max_attempts: 3 do
    if data[:remove_user_roles]
      in_batches do |user_ids, organization_ids|
        with_write { Permissions::Granters::RoleGranter.bulk_revoke(actor_type: "User", actor_ids: user_ids, target_type: "Organization", target_ids: organization_ids) }
      end
    end
  end

  step :remove_org_member_vulnerability_management do
    in_batches(orgs: false) do |user_ids|
      return :skipped if kill_switch_enabled?
      organizations.each do |org|
        org_repo_ids = org.org_repositories.pluck(Arel.sql("/*vt+ IGNORE_MAX_MEMORY_ROWS=1 */ id"))
        org_repo_ids.each_slice(100).flat_map do |subject_ids|
          with_write { Ability.bulk_revoke(actor_type: "User", actor_ids: user_ids, subject_type: "Repository::VulnerabilityManagement", subject_ids: subject_ids) }
        end
      end
    end
  end

  step :revoke_org_apps_management_grants do
    in_batches do |user_ids, organization_ids|
      with_write { Permissions::Granters::RoleGranter.bulk_revoke(role: Role.app_manager_role, actor_type: "User", actor_ids: user_ids, target_type: "Organization", target_ids: organization_ids) }
      integration_ids = Integration.where(owner_type: "Organization", owner_id: organization_ids).pluck(:id)
      with_write { Permissions::Granters::RoleGranter.bulk_revoke(role: Role.app_owner_role, actor_type: "User", actor_ids: user_ids, target_type: "Integration", target_ids: integration_ids) }
    end
  end

  step :revoke_org_member_package_access do
    organizations.each do |org|
      users.each do |user|
        packages = org.packages
        packages.each_slice(100) do |package_batch|
          RemoveOrgMemberPackageAccessV2Job.perform_later(user, package_batch) unless GitHub.enterprise?
        end
      end
    end
  end

  step :unlink_saml_identities do
    return if GitHub.single_business_environment?
    organizations.each do |org|
      if org.saml_sso_enabled?
        cleanup_user_ids = T.must(user_ids) - org.member_ids(actor_ids: T.must(user_ids))
        with_write { ExternalIdentity.unlink_saml_identities(provider: org.saml_provider, user_ids: cleanup_user_ids) }
      end
    end
  end

  step :destroy_sponsors_listing_featured_items do
    return if GitHub.single_business_environment?
    in_batches(orgs: true) do |user_ids, organization_ids|
      listing_ids = SponsorsListing.where(sponsorable_id: organization_ids).pluck(:id)
      next unless listing_ids.any?
      item_ids = SponsorsListingFeaturedItem.where(sponsors_listing_id: listing_ids, featureable_id: user_ids).pluck(:id)
      next unless item_ids.any?
      with_write { SponsorsListingFeaturedItem.where(id: item_ids).destroy_all }
    end
  end

  REMOVE_ORG_USER_EMAIL_SETTINGS_BATCH_SIZE = 30

  step :remove_org_user_email_settings do
    in_batches(batch_size: REMOVE_ORG_USER_EMAIL_SETTINGS_BATCH_SIZE) do |user_ids, org_ids|
      BusinessOrchestrationRemoveOrgUserEmailSettingsJob.perform_later(self, T.must(org_ids), user_ids)
    end
  end

  INSTRUMENT_NOTIFY_REPOSITORY_ACCESS_CHANGED_BATCH_SIZE = 30

  step :notify_repository_access_changed do
    in_batches(orgs: false, batch_size: INSTRUMENT_NOTIFY_REPOSITORY_ACCESS_CHANGED_BATCH_SIZE) do |user_ids|
      BusinessOrchestrationNotifyRepositoryAccessChangedJob.perform_later(self, user_ids)
    end
  end

  INSTRUMENT_REMOVAL_BATCH_SIZE = 25

  step :instrument_removal do
    in_batches(orgs: true, batch_size: INSTRUMENT_REMOVAL_BATCH_SIZE) do |user_ids, organization_ids|
      BusinessOrchestrationInstrumentRemovalJob.perform_later(business_id: business_id, organization_ids: T.must(organization_ids), user_ids: T.must(user_ids), business_team_operation: data[:business_team_operation] || false, reason: data[:reason], actor: actor)
    end
  end

  READ_REPO_BATCH_SIZE = 1000

  sig { params(instrumentation_payloads: T::Array[[String, T::Hash[T.untyped, T.untyped]]]).void }
  def instrument_events(instrumentation_payloads)
    instrumentation_payloads.each do |event|
      name = event.first
      payload = event.last
      instrument_event(name, payload)
    end
  end

  sig { params(name: String, payload: T::Hash[T.untyped, T.untyped]).void }
  def instrument_event(name, payload)
    payload[:timestamp_override] = Time.now
    payload[:actor_id] ||= actor&.id if actor.present?
    GitHub.instrumentation_service.instrument name, payload
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

  sig { override.returns(T.class_of(OrchestrationJob)) }
  def job_class
    RemoveOrganizationMembersCleanupBusinessOrchestrationJob
  end

  sig { override.params(step: OrchestrationStep).returns(T::Boolean) }
  def skip_step?(step)
    kill_switch_enabled?(step.name) || super
  end

  sig { override.returns(T::Boolean) }
  def should_clear_stale_state_before_restarting_stuck?
    true
  end

  private

  sig { params(step: T.nilable(Symbol)).returns(T::Boolean) }
  def kill_switch_enabled?(step = nil)
    T.must(business).kill_switch_enabled?("RemoveOrganizationMembersCleanupBusinessOrchestration##{step || step_name}", feature_flag: :enterprise_teams_killswitch, log_fields: {
      "gh.business.id": business_id,
      "gh.business.orchestration.id": id
    })
  end
end
