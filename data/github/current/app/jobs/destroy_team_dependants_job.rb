# typed: true
# frozen_string_literal: true

class DestroyTeamDependantsJob < ApplicationJob
  queue_as :destroy_team_dependants

  retry_on_dirty_exit
  retry_on_recoverable_exceptions
  retry_on Freno::Throttler::Error, Freno::Error, Freno::Throttler::WaitedTooLong,
    wait: :polynomially_longer, attempts: 20

  def perform(org_id, team_ids_to_info, member_ids = [], ancestor_team_ids = [], options = {})
    # Convert associative array into hash.
    team_ids_to_info = Hash[team_ids_to_info] if team_ids_to_info.is_a?(Array)

    with_write { Team::Destruction::DestroyDependantsOperation.new(org_id, team_ids_to_info).execute }
    # The `member_ids` and `ancestor_team_ids` parameters were added later.
    # To make sure we don't call `DestroySubscriptionsOperation` with the `options`
    # parameter from a previously schedueled job, we skip the operation when
    # member_ids is a Hash. This check can be removed, once there are no old
    # jobs in the queue anymore.
    if member_ids.is_a?(Array) && ancestor_team_ids.is_a?(Array)
      with_write { Team::Destruction::DestroySubscriptionsOperation.new(member_ids, ancestor_team_ids).execute }
    end
  end
end
