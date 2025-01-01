# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class UpdateTeamGroupMappingsJob < ApplicationJob
  queue_as :critical

  class ServiceUnavailable < RuntimeError; end

  retry_on(ServiceUnavailable, wait: 60.seconds, attempts: 3) do |_job, error|
    Failbot.report(error)
  end

  retry_on_dirty_exit
  retry_on_recoverable_exceptions
  retry_on Faraday::ConnectionFailed, wait: :polynomially_longer, attempts: 5
  retry_on Faraday::TimeoutError, wait: :polynomially_longer, attempts: 5

  def perform(team)
    return if team.nil?
    return unless org = team.organization

    tenant = org.team_sync_tenant
    return unless tenant

    group_ids = team.group_mappings.pluck(:group_id)

    response = GroupSyncer.client.update_team_mappings(
      org_id: tenant.organization.global_relay_id,
      team_id: team.global_relay_id,
      group_ids: group_ids,
    )

    if response.error
      raise ServiceUnavailable, response.error.inspect
    end

    with_write { Team::GroupMapping.where(team_id: team.id).touch_all }
  end
end
