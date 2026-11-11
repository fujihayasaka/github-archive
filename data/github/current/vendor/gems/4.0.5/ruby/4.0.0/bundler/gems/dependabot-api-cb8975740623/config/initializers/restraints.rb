# typed: true
# frozen_string_literal: true

require "restraint"
require "sorbet-runtime"
module Restraints
  extend T::Sig

  BRANCH_CHANGE_CONCURRENCY_COUNT = 1 # only allow one change to a branch at a time
  BRANCH_CHANGE_LOCK_TTL = 30.seconds # lock for up to 30 seconds when changing a branch

  # Rubocop wants anonymous blocks, Sorbet doesn't work with anonymous blocks...
  # rubocop:disable Style/ArgumentsForwarding
  # Restrain to running 1 operation at a time that would impact a repository branch.
  sig { params(repo: Repo, branch_name: String, block: T.proc.params(arg0: Restraint::Lock).void).void }
  def self.for_branch_changes(repo:, branch_name:, &block)
    # Repo ids (unsigned 64bit int) have a max value of 18446744073709551615, or 20 chars as a string
    # Branch names on GitHub have a max character length of 255 chars.
    # The max key size therefore should be 276 chars - 20 from repo id as a string + ":" + 255 from branch name.
    # This is a large key to read as a human, but below any key length that should cause issues with redis
    Restraint.lock!("#{repo.id}:#{branch_name}", BRANCH_CHANGE_CONCURRENCY_COUNT, BRANCH_CHANGE_LOCK_TTL, &block)
  end
  # rubocop:enable Style/ArgumentsForwarding
end

ActiveSupport::Notifications.subscribe(/(enqueue_retry|retry_stopped)\.active_job/) do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  error = event.payload.fetch(:error, nil)
  next unless error.is_a?(Restraint::UnableToLock)

  job = event.payload.fetch(:job, nil)
  next unless job

  MetricsClient.increment("job.unable_to_lock_restraint",
                          tags: { job: job.class.name.underscore, queue: job.queue_name })
end
