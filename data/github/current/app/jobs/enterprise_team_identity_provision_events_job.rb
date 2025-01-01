# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: strict
# frozen_string_literal: true

class EnterpriseTeamIdentityProvisionEventsJob < ApplicationJob
  queue_as :enterprise_team_identity_provision_events

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  sig { params(user_id: Integer, external_identity_id: Integer, operation: Symbol).void }
  def perform(user_id:, external_identity_id:, operation:)
    GitHub.logger.info(
      "info.message" => "Starting EnterpriseTeamIdentityProvisionEventsJob",
      "gh.enterprise_team.job.operation" => operation,
      "gh.user.id" => user_id,
      "gh.external_identity.id" => external_identity_id
    )

    # Note: There can be a race condition where the external identity/user does not exist yet in the reader
    associated_business = ExternalIdentity.find_by(id: external_identity_id)&.provider&.business
    user = User.find_by(id: user_id)

    if operation == :provision && associated_business&.feature_flag_enabled_or_raise?(:membership_for_copilot_enterprise_team) && associated_business&.all_users_copilot_team_enabled? # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      enterprise_team = associated_business.enterprise_teams.active.find_by(id: associated_business.all_users_copilot_team_id)
      if enterprise_team
        with_write { EnterpriseTeams::Helper.create_team_membership(enterprise_team, T.must(User.find_by(id: user_id))) }
      end
    end

    group_ids = ExternalIdentityGroupMembership.where(external_identity: external_identity_id).pluck(:external_group_id)
    EnterpriseTeamGroupMapping.active.where(external_group_id: group_ids).find_each do |group_mapping|
      group_mapping.enterprise_team&.instrument_update
      if operation == :provision
        group_mapping.enterprise_team&.instrument_add_member(user) if user
      elsif operation == :deprovision
        group_mapping.enterprise_team&.instrument_remove_member(user) if user
      end
    end

    if operation == :deprovision
      if associated_business.present? && BusinessTeam.enabled_for_enterprise?(business: associated_business)
        if user.present?
          business_team_ids = Orgs.domain.teams.business_team_ids_for(business_id: associated_business.id, user_id: user.id)
          BusinessTeam.where(business_id: associated_business.id, id: business_team_ids).each do |team|
            with_write { team.remove_member(user, caller_type: :business_team) }
          end
        end
      else
        EnterpriseTeamMembership.where(user_id: user_id).includes(:enterprise_team).in_batches do |team_memberships|
          enterprise_teams = team_memberships.filter_map(&:enterprise_team)

          with_write { team_memberships.delete_all }

          enterprise_teams.each do |enterprise_team|
            enterprise_team.instrument_remove_member(user) if user
            enterprise_team.instrument_update
          end
        end
      end
    end

    GitHub.logger.info(
      "info.message" => "Finished EnterpriseTeamIdentityProvisionEventsJob",
      "gh.enterprise_team.job.operation" => operation,
      "gh.user.id" => user_id,
      "gh.external_identity.id" => external_identity_id
    )
  end

  sig { params(payload: T.untyped).void }
  def self.enqueue(payload)
    external_identity_id = payload[:id]
    user_id = payload[:user_id]
    operation = payload[:operation]

    job = EnterpriseTeamIdentityProvisionEventsJob.perform_later(
      user_id: user_id,
      external_identity_id: external_identity_id,
      operation: operation
    )

    GitHub.logger.info(
      "info.message" => "Queuing EnterpriseTeamIdentityProvisionEventsJob",
      "gh.user.id" => user_id,
      "gh.external_identity.id" => external_identity_id,
      "gh.enterprise_team.job.operation" => operation,
      "gh.job.active_job_id" => job.job_id
    ) if job
  end
end
