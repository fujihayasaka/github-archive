# typed: true
# frozen_string_literal: true

module Actions
  class AllowActionsInSelectedReposJob < ApplicationJob
    queue_as :allow_actions_in_selected_repos

    retry_on_dirty_exit

    BATCH_SIZE = 100
    MAX_RUNTIME = 60

    # for all repos with the id above the last_processed_repo_id (i.e. offset) in the org,
    # allow actions if it is selected repos and disallow otherwise
    def perform(org, selected_repo_ids, actor, last_processed_repo_id: 0)
      is_first_run = last_processed_repo_id.zero?
      processed_repo_ids = []
      end_at = Time.now.to_f + MAX_RUNTIME
      org.repositories.where("id > ?", last_processed_repo_id).order(:id).find_each(batch_size: BATCH_SIZE) do |repo|
        Configuration::Entry.throttle do
          with_write do
            if selected_repo_ids.include? repo.id
              repo.allow_actions actor: actor unless repo.actions_allowed_by_owner?
            else
              repo.disallow_actions actor: actor if repo.actions_allowed_by_owner?
            end
          end
        end

        processed_repo_ids.push(repo.id)
        if Time.now.to_f > end_at
          Actions::AllowActionsInSelectedReposJob.perform_later(org, selected_repo_ids, actor, last_processed_repo_id: repo.id)
          instrument_result(is_first_run)
          return
        end

      end

      instrument_result(is_first_run)
    end

    def instrument_result(is_first_run)
      GitHub.dogstats.increment("actions.allow_actions_in_selected_repos_job", tags: ["is_first_run:#{is_first_run}"])
    end
  end
end
