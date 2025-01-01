# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

module Actions
  class AllowSelfHostedRunnersInSelectedReposJob < ApplicationJob
    # Using the same queue as AllowActionsInSelectedReposJob as they are similar in nature and can share resources.
    queue_as :allow_actions_in_selected_repos

    retry_on_dirty_exit

    BATCH_SIZE = 100
    MAX_RUNTIME = 60

    sig { params(organization: Organization, repo_ids: T::Array[Integer], actor: User, last_processed_repo_id: Integer).void }
    def perform(organization, repo_ids, actor, last_processed_repo_id: 0)
      is_first_run = last_processed_repo_id.zero?
      processed_repo_ids = []
      end_at = Time.now.to_f + MAX_RUNTIME

      organization.repositories.where("id > ?", last_processed_repo_id).order(:id).find_each(batch_size: BATCH_SIZE) do |repo|
        Configuration::Entry.throttle do
          with_write do
            if repo_ids.include?(repo.id)
              repo.allow_repo_self_hosted_runners(actor: actor) unless repo.repo_self_hosted_runners_allowed_by_owner?
            else
              repo.disallow_repo_self_hosted_runners(actor: actor) if repo.repo_self_hosted_runners_allowed_by_owner?
            end
          end
        end

        processed_repo_ids.push(repo.id)
        if Time.now.to_f > end_at
          AllowSelfHostedRunnersInSelectedReposJob.perform_later(organization, repo_ids, actor, last_processed_repo_id: repo.id)
          instrument_result(is_first_run)
          return
        end
      end

      instrument_result(is_first_run)
    end

    sig { params(is_first_run: T::Boolean).void }
    def instrument_result(is_first_run)
      GitHub.dogstats.increment("actions.allow_self_hosted_runners_in_selected_repos_job", tags: ["is_first_run:#{is_first_run}"])
    end
  end
end
