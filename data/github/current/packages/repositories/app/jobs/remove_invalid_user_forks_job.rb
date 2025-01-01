# typed: true
# frozen_string_literal: true

# Removes forks owned by users who no longer have access to the fork's network root.
class RemoveInvalidUserForksJob < ApplicationJob
  queue_as :remove_invalid_user_forks
  retry_on_dirty_exit

  def perform(network_id:)
    start = Time.current
    network = RepositoryNetwork.find(network_id)
    with_write { network.remove_invalid_user_forks }
  ensure
    GitHub.dogstats.timing_since("job.remove_invalid_user_forks.time", start)
  end
end
