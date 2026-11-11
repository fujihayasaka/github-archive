# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: strict
# frozen_string_literal: true

class ClearBusinessTeamIndirectOrgAccessJob < ApplicationJob
  include GitHub::Memoizer

  queue_as :clear_business_team_indirect_org_access

  BATCH_SIZE = T.let(100, Integer)
  USERS_BATCH_SIZE = T.let(1000, Integer)
  ENQUEUE_INTERVAL = T.let(30.seconds.to_i, Integer)

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  LOCK_TTL = T.let(5.minutes, Integer)
  GLOBAL_LOCK_KEY = T.let("clear_business_team_indirect_org_access_job", String)

  retry_on GitHub::Restraint::UnableToLock, wait: ->(_executions) { (rand(30..300)).seconds }, attempts: :unlimited

  around_perform do |_job, block|
    GitHub::Restraint.new.lock!(GLOBAL_LOCK_KEY, GitHub.business_team_clear_team_indirect_org_access_job_limit, LOCK_TTL) do
      block.call
    end
  end

  sig { params(business_id: Integer, team_id: Integer, clear_team_roles: T::Boolean, organization_ids: T::Array[Integer], user_ids: T::nilable(T::Array[Integer])).void }
  def perform(business_id:, team_id:, clear_team_roles:, organization_ids:, user_ids: nil)
    return unless user_ids.present? || organization_ids.present?

    business = Business.find_by(id: business_id)
    return unless business

    # Incorporate killswitch
    return if business.kill_switch_enabled?("ClearBusinessTeamIndirectOrgAccessJob", feature_flag: :enterprise_teams_killswitch, log_fields: {
      "gh.team.id": team_id,
      "gh.business.id": business_id
    })

    GitHub.logger.info(
      "info.message" => "Starting clear_business_team_indirect_org_access_job",
      "gh.business.id" => business_id,
      "gh.team.id" => team_id,
      "gh.user.ids" => user_ids,
      "gh.organization.ids" => organization_ids,
    )

    # The business team might already be deleted if called from team.destroy
    user_ids = (BusinessTeam.new(id: team_id)).member_ids if user_ids.blank?

    clear_organization_indirect_access(business, team_id, user_ids, organization_ids, clear_team_roles)

    GitHub.logger.info(
      "info.message" => "Completed clear_business_team_indirect_org_access_job",
      "gh.business.id" => business_id,
      "gh.team.id" => team_id,
      "gh.user.ids" => user_ids,
      "gh.organization.ids" => organization_ids,
    )
  end

  sig { params(business_id: Integer, team_id: Integer, clear_team_roles: T::Boolean, organization_ids: T::Array[Integer], user_ids: T.nilable(T::Array[Integer])).void }
  def self.enqueue(business_id:, team_id:, clear_team_roles:, organization_ids:, user_ids: nil)
    args = {
      business_id: business_id,
      team_id: team_id,
      clear_team_roles: clear_team_roles,
      user_ids: user_ids,
      organization_ids: organization_ids
    }
    enqueue_once_per_interval(kwargs: args, interval: ENQUEUE_INTERVAL)
  end

  private

  sig { returns(User) }
  memoize def actor
    @actor ||= T.let((User.find_by(id: GitHub.context[:actor_id]) || User.ghost), T.nilable(User))
  end

  sig { params(business: Business, team_id: Integer, user_ids: T::Array[Integer], organization_ids: T::Array[Integer], clear_team_roles: T::Boolean).void }
  def clear_organization_indirect_access(business, team_id, user_ids, organization_ids, clear_team_roles)
    GitHub.logger.info(
      "info.message" => "Clearing indirect access for organizations",
      "gh.user.ids" => user_ids,
      "gh.organization.ids" => organization_ids,
      "gh.team.id" => team_id,
      "gh.business.id" => business.id,
    )

    # Batch fetch organizations to avoid N+1 queries
    organizations = Organization.where(id: organization_ids).index_by(&:id)
    return unless organizations.present?
    clear_business_team_indirect_org_access(business, team_id, organizations) if clear_team_roles

    users = User.where(id: user_ids).index_by(&:id)
    return unless users.present?

    # Get users who have both direct and indirect access to the organizations
    direct_and_indirect_member_ids_hash_mapping = {}
    # Process users in batches to avoid overwhelming the query
    user_ids.each_slice(USERS_BATCH_SIZE) do |user_batch|
      batch_memberships = Ability.organization_memberships_for_users(user_ids: user_batch)
      direct_and_indirect_member_ids_hash_mapping.merge!(batch_memberships)
    end

    # Convert to Sets for O(1) lookup instead of O(n)
    membership_sets = direct_and_indirect_member_ids_hash_mapping.transform_values(&:to_set)

    users_to_cleanup_by_orgs = Hash.new([])
    organization_ids_set = organization_ids.to_set
    user_ids.each do |user_id|
      membership_org_ids = membership_sets[user_id] || Set.new
      non_membership_org_ids = organization_ids_set - membership_org_ids
      users_to_cleanup_by_orgs[non_membership_org_ids] += [user_id] unless non_membership_org_ids.empty?
    end

    users_to_cleanup_by_orgs.each do |org_ids, users_to_remove|
      return if business.kill_switch_enabled?("ClearBusinessTeamIndirectOrgAccessJob", feature_flag: :enterprise_teams_killswitch, log_fields: {
        "gh.team.id": team_id,
        "gh.organization.id": org_ids.first,
        "gh.business.id": business.id,
      })

      org_ids = org_ids.to_a

      BusinessOrchestration.remove_organization_members_cleanup(
        actor: actor,
        business: business,
        user_ids: users_to_remove,
        organization_ids: org_ids,
        remove_direct_repo_access: true,
        remove_team_membership: false,
        remove_user_roles: true,
        business_team_operation: true,
      ).execute(synchronous: false)
    end
  end

  sig { params(business: Business, team_id: Integer, organizations: T::Hash[Integer, Organization]).void }
  def clear_business_team_indirect_org_access(business, team_id, organizations)
    GitHub.logger.info(
      "info.message" => "Clearing business team indirect access for organizations",
      "gh.business.id" => business.id,
      "gh.organization.ids" => organizations.keys,
      "gh.team.id" => team_id
    )

    all_direct_and_inherited_repo_ids_for_bt = BusinessTeam.direct_or_inherited_repo_ids(team_id: team_id, affiliation: :immediate)

    revoke_business_team_direct_repo_access(
      business: business,
      organizations: organizations,
      team_id: team_id,
      all_direct_and_inherited_repo_ids_for_bt: all_direct_and_inherited_repo_ids_for_bt
    )

    # Process organizations in batches
    organizations.each_slice(BATCH_SIZE) do |org_batch|
      # Incorporate killswitch between each batch
      return if business.kill_switch_enabled?("ClearBusinessTeamIndirectOrgAccessJob", feature_flag: :enterprise_teams_killswitch, log_fields: {
        "gh.team.id": team_id,
        "gh.organization.id": org_batch.first&.first
      })

      org_batch.each do |_, org|
        revoke_org_roles_for_business_team(business, org, team_id)
      end
    end
  end

  sig { params(org: Organization, user: User).void }
  def revoke_org_roles_for_user(org, user)
    with_write { Permissions::Granters::RoleGranter.new(actor: user, target: org).revoke_if_exists! }
  end

  sig { params(business: Business, org: Organization, team_id: Integer).void }
  def revoke_org_roles_for_business_team(business, org, team_id)
    # Bubble up GrantFailure to sentry
    with_write { Permissions::Granters::RoleGranter.new(actor: BusinessTeam.new(id: team_id), target: org).revoke_if_exists! }
    GitHub.logger.info(
      "info.message" => "Revoked organization roles",
      "gh.business.id" => business.id,
      "gh.team.id" => team_id,
      "gh.organization.id" => org.id,
    )
  end

  sig do
    params(
      business: Business,
      organizations: T::Hash[Integer, Organization],
      team_id: Integer,
      all_direct_and_inherited_repo_ids_for_bt: T::Array[Integer]
    ).void
  end
  def revoke_business_team_direct_repo_access(business:, organizations:, team_id:, all_direct_and_inherited_repo_ids_for_bt:)
    inaccessible_repos_for_team = Repositories.domain.repo_ids_by_org_ids(
      org_ids: organizations.keys,
      include_repo_ids: all_direct_and_inherited_repo_ids_for_bt,
      active_only: false
    )

    Ability.bulk_revoke(
      actor_type: "BusinessTeam",
      actor_ids: [team_id],
      subject_type: "Repository",
      subject_ids: inaccessible_repos_for_team,
    )

    GitHub.logger.info(
      "info.message" => "Revoked business team direct repository access",
      "gh.team.id" => team_id,
      "gh.repositories.count" => inaccessible_repos_for_team.size
    )
  end
end
