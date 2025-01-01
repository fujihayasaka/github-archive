# typed: true
# frozen_string_literal: true

class ClearTeamGroupMappingsJob < ApplicationJob
  default_to_write_connection! # rubocop:todo GitHub/JobsDoNotDefaultToWriteConnection

  queue_as :critical

  class ServiceUnavailable < RuntimeError; end

  retry_on(ServiceUnavailable, wait: 60.seconds, attempts: 3) do |_job, error|
    Failbot.report(error)
  end

  def perform(org_global_relay_id, team_global_relay_id)
    response = GroupSyncer.client.update_team_mappings(
      org_id: org_global_relay_id,
      team_id: team_global_relay_id,
      group_ids: [],
    )

    if response.error
      raise ServiceUnavailable, response.error.inspect
    end
  end
end
