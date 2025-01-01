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

    group_ids = ExternalIdentityGroupMembership.where(external_identity: external_identity_id).pluck(:external_group_id)
    EnterpriseTeamGroupMapping.active.where(external_group_id: group_ids).find_each do |group_mapping|
      group_mapping.enterprise_team&.instrument_update
      if operation == :provision
        group_mapping.enterprise_team&.instrument_add_member(User.find(user_id))
      elsif operation == :deprovision
        group_mapping.enterprise_team&.instrument_remove_member(User.find(user_id))
      end
    end

    with_write do
      EnterpriseTeamMembership.where(user_id: user_id).find_each do |team_membership|
        team_membership.destroy
      end
    end if operation == :deprovision

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
