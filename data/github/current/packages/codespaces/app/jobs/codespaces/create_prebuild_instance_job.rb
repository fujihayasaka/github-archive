# typed: true
# frozen_string_literal: true

module Codespaces
  class CreatePrebuildInstanceJob < CodespacesJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
    locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC

    RETRYABLE_ERRORS = [
      ActiveRecord::RecordNotFound,
      Codespaces::Client::BadResponseError,
      Codespaces::Client::TimeoutError
    ]

    # will retry twice over ~30 seconds
    retry_on *RETRYABLE_ERRORS,
      wait: :polynomially_longer, attempts: 3 do |_job, error|
        raise error
      end

    attr_accessor :repository,
                  :pool_code,
                  :location,
                  :vscs_target,
                  :vscs_target_url,
                  :environment_options,
                  :branch
    attr_reader :entry_point

    def perform(
      repository:,
      pool_code:,
      location:,
      vscs_target: Codespaces::Vscs.default_target,
      vscs_target_url: nil,
      environment_options: {},
      branch: nil,
      entry_point: nil
    )

      with_write do
        Codespaces::CreatePrebuildInstance.call(
          repository: repository,
          pool_code: pool_code,
          location: location,
          vscs_target: vscs_target,
          vscs_target_url: vscs_target_url,
          environment_options: environment_options,
          branch: branch,
          entry_point: entry_point
        )
      end

    rescue *RETRYABLE_ERRORS
      raise
    rescue Codespaces::Error, Aqueduct::Worker::JobKilled => e
      if e.class == Aqueduct::Worker::JobKilled
        GitHub.dogstats.increment("codespaces.create_prebuild_instance_job.dirty_exit", tags: stats_tags)
      end
      raise
    end

    def stats_tags
      location = arguments.first&.fetch(:location)
      vscs_target = arguments.first&.fetch(:vscs_target, Codespaces::Vscs.default_target)
      Codespaces::StatsTagger.new(location: location, vscs_target: vscs_target).datadog_tags
    end
  end
end
