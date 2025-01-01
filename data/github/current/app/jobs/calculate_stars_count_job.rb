# typed: true
# frozen_string_literal: true

# Recalculates the cached number of stars when any of the starred users' spammy
# status changes. We hide spammy users, so this number has to match.
#
# The methods that calculate the stars count already know to exclude spammy
# users. We just have to run them.
class CalculateStarsCountJob < ApplicationJob
  include ActiveJob::InitiallyEnqueuedAt
  include Scientist
  include Repositories::Domain::Provider

  queue_as :calculate_stars_count

  retry_on_dirty_exit

  # Discard the job if the user has been deleted before the job runs
  discard_on ActiveRecord::RecordNotFound

  BATCH_SIZE = 100

  # user            - The active record user object
  # offset_id       - Integer NotificationEntry id offset for working job in small batches
  # start_time      - The time that the job was initially kicked off. Used to track total duration accross all batches.
  def perform(user, offset_id = 0, start_time = initially_enqueued_at)
    # Grab starrables in batches of 100 to avoid a large IN-clause against repositories
    starred_repositories = user.stars.repositories
    starred_repositories = starred_repositories.where("starrable_id > ?", offset_id) if offset_id
    starred_repositories = starred_repositories.limit(BATCH_SIZE).order(:starrable_id)
    starred_repository_ids = starred_repositories.distinct.pluck(:starrable_id)
    batch = Repository.where(id: starred_repository_ids).to_a
    if batch.size > 0
      Repository.throttle do
        batch.each do |repo|
          count = Stars.domain.repository_star_count(T.must(repo.id))
          with_write do
            repositories_domain.update_stargazer_count(repository_id: T.must(repo.id), count: count)
          end
        end
      end
    end

    if starred_repository_ids.size < BATCH_SIZE
      duration = (Time.now.utc - T.cast(start_time, Time)) * 1_000
      GitHub.dogstats.distribution("calculate_stars_count.dist.duration", duration)
    else
      CalculateStarsCountJob.perform_later(user, starred_repository_ids.last, start_time)
    end
  end

  def starred_repository_ids(scope)
    ids = scope.where_values_hash["id"]
    ids = [ids] unless ids.is_a?(Array)
    ids
  end

  def filter_repository_ids(repo_ids, offset_id)
    repo_ids.sort.select { |id| id > offset_id }.take(BATCH_SIZE)
  end
end
