# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class ClearGraphDataOnBlockJob < ApplicationJob
  queue_as :clear_graph_data_on_block

  retry_on_dirty_exit

  def perform(blocker_id, blockee_id)
    @blocker = User.find(blocker_id)
    @blockee = User.find(blockee_id)

    # Get all the repos by the blocker that the blockee has contributed to
    # clear all their graph data
    @blocker.repositories.find_in_batches(batch_size: 10000) do |group|
      Repository.throttle do
        group.each do |repo|
          if repo.contributor? @blockee
            ClearRepositoriesGraphDataJob.perform_later(repo.id)
          end
        end
      end
    end
  end
end
