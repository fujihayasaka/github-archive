# typed: true
# frozen_string_literal: true

class ClearEnterpriseTeamGroupMappingsJob < ApplicationJob
  default_to_write_connection! # rubocop:todo GitHub/JobsDoNotDefaultToWriteConnection

  queue_as :clear_enterprise_team_group_mappings

  locked_by timeout: 5.minutes, key: DEFAULT_LOCK_PROC

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  # Execute a soft delete on the ETGM, by setting the `delete_at` column to the current timestamp
  # Chose to iterate instead of `update_all` so we get active record callbacks. If performance becomes an issue
  # when we are supporting more than one ETGM at a time we can revisit.
  sig do
    params(
      external_group_id: T.nilable(Integer)
    )
    .void
  end
  def perform(external_group_id)
    GitHub.logger.info(
      "info.message" => "Starting clear_enterprise_team_group_mappings_job",
      "gh.external_group.id" => external_group_id
    )
    mappings = EnterpriseTeamGroupMapping.transaction do
      EnterpriseTeamGroupMapping.where(external_group_id: external_group_id).each(&:soft_delete)
    end
    GitHub.logger.info(
      "info.message" => "Finished clear_enterprise_team_group_mappings_job",
      "gh.external_group.id" => external_group_id,
      "gh.enterprise_team.group_mapping.count" => mappings.count,
      "gh.enterprise_team.group_mapping.ids" => mappings.map(&:id)
    )
  end
end
