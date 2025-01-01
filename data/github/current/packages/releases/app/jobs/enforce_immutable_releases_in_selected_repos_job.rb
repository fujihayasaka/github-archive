# typed: true
# frozen_string_literal: true

class EnforceImmutableReleasesInSelectedReposJob < ApplicationJob
  queue_as :enforce_immutable_releases_in_selected_repos

  retry_on_dirty_exit

  # Process repositories in batches to avoid long-running jobs.
  BATCH_SIZE = 100

  # Maximum runtime for the job before a new job is scheduled.
  MAX_RUNTIME = 60

  # Iterate through all repositories in the organization (with ID above the last_processed_repo_id).
  # For each repository, check if it is in the selected repositories list. If it is, enforce immutable releases;
  # otherwise, remove the enforcement.
  #
  # Processing is done in batches to avoid long-running jobs. If processing exceeds MAX_RUNTIME, a new job is
  # scheduled to continue from the last processed repository ID.
  def perform(org, selected_repo_ids, actor, last_processed_repo_id: 0)
    is_first_run = last_processed_repo_id.zero?
    config = Releases::ImmutableOrganizationConfig.new(org)

    # Time tracking for job execution
    end_at = Time.now.to_f + MAX_RUNTIME

    org.repositories.where("id > ?", last_processed_repo_id).order(:id).find_each(batch_size: BATCH_SIZE) do |repo|
      Configuration::Entry.throttle do
        with_write do
          if selected_repo_ids.include? repo.id
            config.enforce_immutable_releases_for_repo_ids([repo.id], actor: actor)
          else
            config.unenforce_immutable_releases_for_repo_ids([repo.id], actor: actor)
          end
        end
      end

      if Time.now.to_f > end_at
        EnforceImmutableReleasesInSelectedReposJob.perform_later(org, selected_repo_ids, actor, last_processed_repo_id: repo.id)
        instrument_result(is_first_run)
        return
      end

    end

    instrument_result(is_first_run)
  end

  def instrument_result(is_first_run)
    GitHub.dogstats.increment("releases.enforce_immutable_releases_in_selected_repos_job", tags: ["is_first_run:#{is_first_run}"])
  end

  def failbot_context
    {
      "#job" => self.class.name,
      "gh.org.id" => arguments.first.id,
    }
  end
end
