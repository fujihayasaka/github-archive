# typed: strict
# frozen_string_literal: true

class EnterpriseTeamOrganizationMappingJob < ApplicationJob
  include ActiveJob::InitiallyEnqueuedAt
  extend T::Sig

  queue_as :enterprise_team_organization_mapping
  after_perform :queue_reconciliation_job

  retry_on_dirty_exit
  retry_on_recoverable_exceptions
  retry_on GitHub::Restraint::UnableToLock, wait: 5.minutes, attempts: 10

  BATCH_SIZE = 1000

  sig { params(enterprise_team_id: Integer, organization_id: T.nilable(Integer)).void }
  def perform(enterprise_team_id, organization_id: nil)
    GitHub.logger.info(
      "info.message" => "Starting enterprise_team_organization_mapping_job",
      "gh.enterprise_team.id" => enterprise_team_id
    )

    EnterpriseTeamOrganizationMapping.job_restraint_lock!(enterprise_team_id: enterprise_team_id) do
      GitHub.logger.info(
        "info.message" => "Acquired EnterpriseTeamOrganizationMapping job restraint lock",
        "gh.enterprise_team.id" => enterprise_team_id,
      )

      @enterprise_team_id = T.let(enterprise_team_id, T.nilable(Integer))
      @organization_id = T.let(nil, T.nilable(Integer))
      @skip_reconciliation_job = T.let(false, T.nilable(T::Boolean))

      # Soft-deleted EnterpriseTeams are not considered here. The records alongside any ESM roles will be cleaned up
      # by the EnterpriseTeamOrganizationReconciliationJob enqueued in the after_perform callback.
      enterprise_team = EnterpriseTeam.active.find_by(id: enterprise_team_id)
      unless validate_enterprise_team?(enterprise_team)
        GitHub.logger.error({
          "exception.message" => "Validation failed for enterprise_team_organization_mapping_job",
          "gh.enterprise_team.id" => enterprise_team_id
        })
        return
      end
      enterprise_team = T.must(enterprise_team)

      items_to_create = T.let([], T::Array[T.untyped])

      organization_ids = if organization_id
        [organization_id]
      else
        RepositorySecurityCenterConfig
          .where(ghas_enabled: true, owner_type: "ORGANIZATION", business: enterprise_team.business)
          .distinct
          .pluck(:owner_id)
      end

      # How many mappings can we create till we hit the max limit?
      left_to_create = EnterpriseTeam.max_sync_organizations - enterprise_team.enterprise_team_organization_mappings.count

      # Gather all teams and mappings that need to be created
      Organization.where(id: organization_ids).find_in_batches do |organizations_batch|
        organizations_batch.each do |organization|
          next if EnterpriseTeam.disabled_for_organization?(organization: organization)

          mapping = EnterpriseTeamOrganizationMapping.find_or_initialize_by(
            enterprise_team: enterprise_team,
            organization: organization
          )

          if mapping.team_id.nil? && left_to_create > 0
            items_to_create << {
              team: team_attributes(enterprise_team, organization),
              mapping: mapping_attributes(enterprise_team, organization)
            }
            GitHub.logger.info(
              "info.message" => "Computed team mappings to create for enterprise_team_organization_mapping_job",
              "gh.enterprise_team.id" => enterprise_team_id,
              "gh.enterprise_team.organization_mapping.count" => items_to_create.count
            )
            left_to_create -= 1
          elsif mapping.team_id.nil? && left_to_create <= 0
            GitHub.logger.info(
              "info.message" => "Max_Sync_Organizations limit reached - mapping not created for enterprise_team_organization_mapping_job",
              "gh.enterprise_team.id" => enterprise_team_id,
              "gh.organization.id" => organization.id
            )
          else
            GitHub.logger.info(
              "info.message" => "Mapping and team already exist for enterprise_team_organization_mapping_job",
              "gh.enterprise_team.id" => enterprise_team_id,
              "gh.organization.id" => organization.id,
              "gh.team.id" => mapping.team_id
            )
          end
        end
      end

      if items_to_create.count == 1
        @organization_id = items_to_create.first[:mapping][:organization_id]
      elsif items_to_create.count == 0 && !organization_id.nil?
        @skip_reconciliation_job = true
        GitHub.logger.info(
          "info.message" => "Max_Sync_Organizations limit reached - Skipping EnterpriseTeamOrganizationReconciliationJob",
          "gh.enterprise_team.id" => enterprise_team_id,
          "gh.organization.id" => organization_id
        )
      end

      create_teams_and_mappings(items_to_create, business: T.must(enterprise_team.business)) if items_to_create.any?

      GitHub.logger.info(
        "info.message" => "Created team mappings for enterprise_team_organization_mapping_job",
        "gh.enterprise_team.id" => enterprise_team_id,
        "gh.enterprise_team.organization_mapping.count" => items_to_create.count
      )

      sync_security_manager_roles(enterprise_team) if EnterpriseTeam.enabled_for_organization_security_manager?(enterprise_team.business)

      GitHub.logger.info(
        "info.message" => "Finished enterprise_team_organization_mapping_job",
        "gh.enterprise_team.id" => enterprise_team_id
      )
    end
  end

  private

  sig { void }
  def queue_reconciliation_job
    return if @skip_reconciliation_job
    return if @enterprise_team_id.nil?
    return unless validate_enterprise_team?(EnterpriseTeam.unscoped.find_by(id: @enterprise_team_id))

    EnterpriseTeamOrganizationReconciliationJob.enqueue(
      enterprise_team_id: Integer(@enterprise_team_id),
      organization_id: @organization_id,
      out_of_sync_time: initially_enqueued_at
    )
  end

  sig { params(items_to_create: T::Array[T.untyped], business: Business).void }
  def create_teams_and_mappings(items_to_create, business:)
    if EnterpriseTeam.enabled_for_organizations?(business:)
      Instrumentation.suppressing do
        ActiveRecord::Base.connected_to(role: :writing) do
          ApplicationRecord::Domain::Users.transaction do
            items_to_create.each_slice(BATCH_SIZE) do |batch|
              # Create teams one by one, because we need the team_id to insert the mappings
              created_teams = batch.map { |item| Team.create!(item[:team]) }
              # Prepare the mappings to insert
              mappings_to_insert = created_teams.map.with_index do |team, index|
                batch[index][:mapping].merge(team_id: team.id)
              end
              # Insert the mappings
              EnterpriseTeamOrganizationMapping.insert_all(mappings_to_insert)
            end
          end
        end
      end
    else
      ActiveRecord::Base.connected_to(role: :writing) do
        ApplicationRecord::Domain::Users.transaction do
          items_to_create.each_slice(BATCH_SIZE) do |batch|
            # Create teams one by one, because we need the team_id to insert the mappings
            created_teams = batch.map { |item| Team.create!(item[:team]) }
            # Prepare the mappings to insert
            mappings_to_insert = created_teams.map.with_index do |team, index|
              batch[index][:mapping].merge(team_id: team.id)
            end
            # Insert the mappings
            EnterpriseTeamOrganizationMapping.insert_all(mappings_to_insert)
          end
        end
      end
    end
  end

  sig { params(enterprise_team: EnterpriseTeam).void }
  def sync_security_manager_roles(enterprise_team)
    ActiveRecord::Base.connected_to(role: :writing) do
      has_security_manager_assignment = enterprise_team.enterprise_team_assignments.where(assignment_type: :security_manager).exists?

      enterprise_team
        .enterprise_team_organization_mappings
        .includes(:team)
        .find_each do |mapping|
          if has_security_manager_assignment
            SecurityProduct::SecurityManagerRole.grant!(mapping.team)
          else
            SecurityProduct::SecurityManagerRole.revoke!(mapping.team, caller: :enterprise_team)
          end
        end
    end
  end

  sig { params(enterprise_team: EnterpriseTeam, organization: Organization).returns(T::Hash[T.untyped, T.untyped]) }
  def team_attributes(enterprise_team, organization)
    {
      organization_id: organization.id,
      name: candidate_name(enterprise_team, organization),
      description: "Synced from enterprise team '#{enterprise_team.name}'",
      privacy: :closed,
      notification_setting: Team::NOTIFICATIONS_DISABLED
    }
  end

  sig { params(enterprise_team: EnterpriseTeam, organization: Organization).returns(T::Hash[T.untyped, T.untyped]) }
  def mapping_attributes(enterprise_team, organization)
    {
      enterprise_team_id: enterprise_team.id,
      organization_id: organization.id
    }
  end

  sig { params(enterprise_team: EnterpriseTeam, organization: Organization).returns(String) }
  def candidate_name(enterprise_team, organization)
    base_name = enterprise_team.name
    index = 0
    candidate_name = base_name
    while Team.find_by(organization: organization, name: candidate_name)
      index += 1
      candidate_name = "#{base_name}-#{index}"
    end

    candidate_name
  end

  sig { params(enterprise_team: T.nilable(EnterpriseTeam)).returns(T::Boolean) }
  def validate_enterprise_team?(enterprise_team)
    return false unless enterprise_team

    # Validate Feature Flag
    business = enterprise_team.business
    EnterpriseTeam.enabled_for_organizations?(business: business)
  end
end
