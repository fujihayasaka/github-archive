# typed: true
# frozen_string_literal: true

class CodespacesProvisionJob < CodespacesJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
  class ForkNotReady < StandardError; end

  locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC

  RETRYABLE_ERRORS = [
    ActiveRecord::RecordNotFound,
    Codespaces::Client::BadResponseError,
    Codespaces::Client::TimeoutError,
    Codespaces::Tokens::Error,
    GitHub::Redis::Mutex::LockError,
  ]

  ALL_RETRYABLE_ERRORS = [
    *RETRYABLE_ERRORS,
    Codespaces::FindEnvironment::NotFoundError,
    ActiveRecord::RecordNotUnique,
    ForkNotReady
  ]

  # will retry twice over ~30 seconds
  retry_on *T.unsafe(RETRYABLE_ERRORS), wait: :polynomially_longer, attempts: 3 do |job, error|
    job.provisioning_failed(error)
  end

  # These are raised effectively while we are "polling" for a previously timed
  # out environment creation to eventually finish being created. We want to
  # allow more of these retries over a longer period of time than the normal
  # retries.
  retry_on Codespaces::FindEnvironment::NotFoundError, attempts: 10 do |job, error|
    job.provisioning_failed(error)
  end

  # If we attempt to provision a plan (or resource group) and hit a `RecordNotUnique`
  # error from a race condition this will allow us to retry the job which should
  # subsequently find the conflicting record.
  retry_on ActiveRecord::RecordNotUnique, attempts: 1 do |job, error|
    job.provisioning_failed(error)
  end

  # Raised in perform if the codespace's backing repo was forked but git is not
  # yet ready on the fork. We retry until it becomes ready.
  retry_on ForkNotReady,
    wait: :polynomially_longer, attempts: 10 do |job, error|
    job.provisioning_failed(error)
  end

  def perform(codespace:, environment_options: {}, entry_point: nil)
    # If the backing repository is `empty?` then the we cannot really provision
    # the codespace fully. It would work on our side but would break when VSCS
    # attempts to clone the repo. Raising here allows us to retry until it's
    # not `empty?`.
    raise ForkNotReady if codespace.repository.empty?

    # Return early if the codespace is provisioned already.
    return if codespace.provisioned?
    # If we already marked this codespace as failed then there's no reason to try provisioning here. This can happen
    # now because we now immediately enqueue a delayed run of this job in case we are interrupted in Create by
    # a GLB timeout. Without this check we can go on and attempt to mint a token but CleanUpStuckProvisioningJob
    # could have run between now and some token minting code that re-fetches the codespace from the database which
    # would find nothing and blow up.
    return if codespace.failed?
    # And finally, if a codespace is successfully provisioned and then immediately deleted (looking at you `snek-testing-bot`)
    # then we can arrive here with a `deprovisioned`/deleted codespace by the time the pessimistically enqueued job
    # runs. Rails' GlobalID automatically does `Codespace.unscoped.find` to deserialize itself to the job which is how
    # we can even get here but then token minting just does a `Codespace.find` in its internals which will fail to find
    # the codespace because of the default `active` scope we apply.
    return if codespace.deleted?

    github_token = Codespaces::Tokens.mint_github_token(codespace.owner, codespace, entry_point: entry_point)

    with_write do
      Codespace.throttle_with_retry do
        Codespaces::ProvisionEnvironment.call(
          codespace,
          environment_options: environment_options,
          github_token: github_token
        )
      end
    end
  rescue *ALL_RETRYABLE_ERRORS => e
    # Silence repository_not_found errors
    if e.class == Codespaces::Tokens::Error && e.message.include?("repository_not_found")
      with_write do
        Codespace.throttle_with_retry { codespace.failed! }
      end
    else
      raise
    end
  rescue StandardError, Aqueduct::Worker::JobKilled => e # rubocop:todo Lint/RescueException
    if e.class == Aqueduct::Worker::JobKilled
      GitHub.dogstats.increment("codespaces_provision_job.dirty_exit")
    end
    with_write do
      Codespace.throttle_with_retry { codespace.failed! }
    end
    raise
  end

  def provisioning_failed(error)
    codespace = arguments.first[:codespace]
    with_write do
      Codespace.throttle_with_retry { codespace&.failed! }
    end

    raise error
  end
end
