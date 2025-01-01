# typed: true
# frozen_string_literal: true

# Finalizes the enrollment of a Repository in Dependabot by sending any outstanding
# updates to Dependabot for processing.
class Dependabot::RepositoryEnrollJob < ApplicationJob
  queue_as :dependabot
  include GitHub::RateLimitable

  class RateLimitedError < StandardError; end

  MAX_JOBS_PER_INSTALLATION_PER_MINUTE = 5

  retry_on_dirty_exit
  retry_on RateLimitedError, wait: :polynomially_longer do |job, _error|
    GitHub.logger.error("RateLimitedError",
      "code.namespace": "Dependabot::RepositoryEnrollJob",
      "code.function": "perform",
      "gh.repo.id": job.repository_id,
    )

    GitHub.dogstats.increment("dependabot.repository_enroll_job.rate_limited")
  end

  def self.enqueue(repository)
    return false if repository.owner.spammy?

    perform_later(repository.id)
  end

  def perform(*args)
    GitHub.dogstats.increment("dependabot.repository_enroll_job.started")

    repository = Repositories::Public.find_active!(repository_id)
    # Dependabot should avoid creating RepositoryDependencyUpdate rows and dispatching
    # jobs to the service for spammy users as it is both a waste of resources and a
    # potential abuse vector
    return false if repository.owner&.spammy?

    # Enrollment will generate a large volume of RepositoryDependencyUpdate
    # rows, so lets throttle for safety.
    record_time "dependabot.repository_enroll_job.time" do
      throttle_rate_limited_request_updates_for_repository(repository)
    end

    GitHub.dogstats.increment("dependabot.repository_enroll_job.completed")
  end

  def repository_id
    arguments.first
  end

  private

  def throttle_rate_limited_request_updates_for_repository(repository)
    RepositoryDependencyUpdate.throttle do
      with_rate_limit(repository) do
        with_write do
          RepositoryDependencyUpdate.request_for_repository(repository, trigger: :install)
        end
      end
    end
  end

  def record_time(metric_name)
    start_time = GitHub::Dogstats.monotonic_time
    yield
  ensure
    elapsed = GitHub::Dogstats.duration(start_time)
    GitHub.dogstats.distribution(metric_name, elapsed)
  end

  def with_rate_limit(repository)
    dependabot_install = repository.dependabot_install
    return yield unless dependabot_install

    rate_limit_key = "dependabot-dependency-update:#{dependabot_install.id}"
    if rate_limit_increment(rate_limit_key, { max_tries: MAX_JOBS_PER_INSTALLATION_PER_MINUTE, ttl: 60 }).at_limit?
      raise RateLimitedError
    else
      yield
    end
  end
end
