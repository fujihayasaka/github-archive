# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: false
# frozen_string_literal: true

class ClearGraphDataOnSpammyJob < ApplicationJob
  queue_as :clear_graph_data_on_spammy

  retry_on_dirty_exit

  def perform(user_id)
    repo_ids = User.find_by_id(user_id).try(:unfiltered_contributed_repository_ids) || []
    ClearRepositoriesGraphDataJob.perform_later(repo_ids)
  end
end
