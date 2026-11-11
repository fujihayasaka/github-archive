# typed: strict
# frozen_string_literal: true

# Scheduled job that purges non-collaborator notification subscriptions on
# repositories archived for longer than GRACE_PERIOD.
#
# PK-walks repos whose `archived_at` falls within a rolling WINDOW_SIZE just
# past the grace period, tracked via a durable Notifications::KV cursor.
#
# Single-instance via `locked_by`. Each `perform` drains the in-flight repo
# fully before checking the time budget, so by design one huge repo can extend a run
# beyond `MAX_RUNTIME` (bounded by `LOCK_TIMEOUT`).
class PurgeArchivedRepositorySubscriptionsJob < ApplicationJob
  CURSOR_KEY = "purge_archived_repo_subscriptions.cursor_id"
  GRACE_PERIOD = T.let(6.months, ActiveSupport::Duration)
  WINDOW_SIZE = T.let(2.weeks, ActiveSupport::Duration)
  REPO_BATCH_SIZE = 50
  # Maximum span of repository ids scanned by a single batch query.
  # Targets ~100ms p95 query time on warm replica buffer pool. Tunable
  # from production `batch_query_time_ms` percentiles.
  ID_STRIDE = 100_000
  SUBSCRIBER_BATCH_SIZE = 1000
  MAX_RUNTIME = T.let(4.minutes, ActiveSupport::Duration)
  MAX_QUEUE_DEPTH = 50_000
  # Downstream queue where the `Newsies::DeleteAllForListAndUsersJob` we
  # enqueue runs (it inherits `Newsies::MaintenanceBaseJob`, which pins
  # this queue). We backpressure against it rather than our own queue.
  DOWNSTREAM_QUEUE = T.let(:notifications_maintenance, Symbol)
  QUEUE_CHECK_INTERVAL = T.let(30.seconds, ActiveSupport::Duration)
  INTERVAL = T.let(1.hour, ActiveSupport::Duration)
  MAX_ERRORS_PER_RUN = 5
  # Headroom over MAX_RUNTIME for an in-flight repo to finish draining: the
  # deadline is only checked between repos, so a single huge repo can run long.
  LOCK_TIMEOUT = T.let(30.minutes, ActiveSupport::Duration)

  schedule interval: INTERVAL, condition: -> { !GitHub.enterprise? }
  locked_by timeout: LOCK_TIMEOUT, key: DEFAULT_LOCK_PROC
  queue_as :subscriptions_maintenance
  retry_on_dirty_exit
  retry_on_recoverable_exceptions
  exempt_from_tenant_context_requirement

  # Replicas covering the read paths exercised here:
  # - Repositories: scanner query and `max_repository_id` bound
  # - Mysql2: Notifications cluster (`Newsies::*Subscription` counts, subscriber listing)
  # - IamAbilities + Mysql1 + Iam + Configurations + Collab: read paths transitively
  #   used by the public-repo Ability queries and `async_readable_by?` on private repos
  use_replicas(
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Repositories,
  )

  sig { void }
  def perform
    cursor_id = T.let(load_cursor, Integer)
    cutoff = GRACE_PERIOD.ago
    window_start = (GRACE_PERIOD + WINDOW_SIZE).ago

    # Upper bound for the cursor walk. O(1) PK lookup; per-batch
    # `archived_at < cutoff` filter still excludes ineligible repos.
    max_repository_id = T.let(Repository.maximum(:id) || 0, Integer)
    GitHub.dogstats.gauge("purge_archived_repo_subscriptions.max_repository_id", max_repository_id)

    end_at = Time.current + MAX_RUNTIME
    repos_processed = T.let(0, Integer)
    errors_this_run = T.let(0, Integer)
    last_queue_check = T.let(Time.at(0), Time)
    last_processed_repo_id = T.let(0, Integer)

    while Time.current < end_at
      # Backpressure against the downstream queue where the delete jobs run.
      if Time.current - last_queue_check >= QUEUE_CHECK_INTERVAL
        depth = self.class.queue_depth(queue: DOWNSTREAM_QUEUE)
        if depth > MAX_QUEUE_DEPTH
          GitHub.dogstats.increment("purge_archived_repo_subscriptions.backpressure_pause")
          break
        end
        last_queue_check = Time.current
      end

      # Cycle complete: cursor has walked the full eligible id range.
      if cursor_id >= max_repository_id
        GitHub.dogstats.increment("purge_archived_repo_subscriptions.cycle_complete")
        reset_cursor
        cursor_id = 0
        break
      end

      # Bound the per-query scan to ID_STRIDE rows of the clustered index.
      # Without an index on `archived_at`, this caps worst-case rows-examined
      # per query (matches in the narrow window are sparse).
      upper = [cursor_id + ID_STRIDE, max_repository_id].min

      batch_query_start = Time.current
      repositories = build_repository_query(cursor_id, upper, cutoff, window_start)
      batch_query_ms = (Time.current - batch_query_start) * 1_000
      GitHub.dogstats.distribution("purge_archived_repo_subscriptions.batch_query_time_ms", batch_query_ms)

      repositories.each do |repository|
        break if errors_this_run >= MAX_ERRORS_PER_RUN

        repository_id = repository.id
        begin
          start_time = Time.current
          purge_non_collaborator_subscriptions(repository)
          elapsed_ms = (Time.current - start_time) * 1_000
          visibility_tag = repository.public? ? "visibility:public" : "visibility:private"
          GitHub.dogstats.distribution("purge_archived_repo_subscriptions.repo_processing_time", elapsed_ms, tags: [visibility_tag])

          repos_processed += 1
        rescue StandardError => e
          GitHub.dogstats.increment("purge_archived_repo_subscriptions.repo_error")
          NotificationsFailbot.report(e, "gh.repository.id": repository_id)
          errors_this_run += 1
        end

        cursor_id = repository_id
        last_processed_repo_id = repository_id
      end

      # Stride exhausted with no more matches: jump cursor to `upper` so the
      # empty/sparse range isn't re-scanned. Only safe when the batch fully
      # drained; if MAX_ERRORS_PER_RUN broke the loop early, leave the cursor
      # at the last attempted repo so the unattempted ones get retried.
      drained_batch = errors_this_run < MAX_ERRORS_PER_RUN
      if drained_batch && repositories.size < REPO_BATCH_SIZE && cursor_id < upper
        cursor_id = upper
      end
      save_cursor(cursor_id)
      GitHub.dogstats.increment("purge_archived_repo_subscriptions.batch_processed")

      break if errors_this_run >= MAX_ERRORS_PER_RUN
    end

    GitHub.dogstats.gauge("purge_archived_repo_subscriptions.repos_processed_per_run", repos_processed)
    GitHub.dogstats.gauge("purge_archived_repo_subscriptions.cursor_id", cursor_id)
    GitHub.dogstats.gauge("purge_archived_repo_subscriptions.last_processed_repo_id", last_processed_repo_id)
  end

  private

  # Drain all subscribers for a single archived repo, deleting subscriptions
  # for non-collaborators.
  sig { params(repository: Repository).void }
  def purge_non_collaborator_subscriptions(repository)
    visibility_tag = repository.public? ? "visibility:public" : "visibility:private"
    subscriber_offset = T.let(0, Integer)

    loop do
      batch = Notifications::Subscriptions.all_repository_subscriber_ids(
        repository.id, after: subscriber_offset, limit: SUBSCRIBER_BATCH_SIZE
      )
      break if batch.empty?

      collab_ids = collaborator_user_ids(repository, batch)
      non_collab_ids = batch - collab_ids.to_a

      if non_collab_ids.any?
        emit_subscription_type_counts(repository, non_collab_ids, visibility_tag)
        Notifications::Subscriptions.async_delete_list_subscriptions_for_users(
          list: Notifications::Subject.new(type: "Repository", id: repository.id),
          user_ids: non_collab_ids,
        )
        GitHub.dogstats.count("purge_archived_repo_subscriptions.non_collab_ids_purged", non_collab_ids.size, tags: [visibility_tag])
      end

      break if batch.size < SUBSCRIBER_BATCH_SIZE
      subscriber_offset = T.must(batch.last)
    end
  end

  # Emit per-type counts of rows the downstream `DeleteAllForListAndUsersJob`
  # will remove for this batch.
  sig { params(repository: Repository, user_ids: T::Array[Integer], visibility_tag: String).void }
  def emit_subscription_type_counts(repository, user_ids, visibility_tag)
    list = Newsies::List.new("Repository", repository.id)

    list_count = Newsies::ListSubscription.for_list(list).for_users(user_ids).count
    thread_count = Newsies::ThreadSubscription.for_list(list).for_users(user_ids).count
    thread_type_count = Newsies::ThreadTypeSubscription.for_list(list).for_users(user_ids).count

    GitHub.dogstats.count("purge_archived_repo_subscriptions.subscriptions_enqueued_for_deletion", list_count, tags: ["type:list", visibility_tag])
    GitHub.dogstats.count("purge_archived_repo_subscriptions.subscriptions_enqueued_for_deletion", thread_count, tags: ["type:thread", visibility_tag])
    GitHub.dogstats.count("purge_archived_repo_subscriptions.subscriptions_enqueued_for_deletion", thread_type_count, tags: ["type:thread_type", visibility_tag])
  end

  sig { params(repository: Repository, user_ids: T::Array[Integer]).returns(T::Set[Integer]) }
  def collaborator_user_ids(repository, user_ids)
    if repository.public?
      collaborator_user_ids_for_public_repo(repository, user_ids)
    else
      collaborator_user_ids_for_private_repo(repository, user_ids)
    end
  end

  sig { params(repository: Repository, user_ids: T::Array[Integer]).returns(T::Set[Integer]) }
  def collaborator_user_ids_for_public_repo(repository, user_ids)
    collab_set = T.let(
      Ability.where(
        subject_type: "Repository", subject_id: repository.id,
        actor_type: "User", actor_id: user_ids,
      ).pluck(:actor_id).to_set,
      T::Set[Integer],
    )

    team_ids = Ability.where(
      subject_type: "Repository", subject_id: repository.id,
      actor_type: "Team",
    ).pluck(:actor_id)

    if team_ids.any?
      team_member_ids = Ability.where(
        subject_type: "Team", subject_id: team_ids,
        actor_type: "User", actor_id: user_ids,
      ).pluck(:actor_id)
      collab_set.merge(team_member_ids)
    end

    if repository.in_organization?
      org_member_ids = Ability.where(
        subject_type: "Organization", subject_id: repository.owner_id,
        actor_type: "User", actor_id: user_ids,
      ).pluck(:actor_id)
      collab_set.merge(org_member_ids)
    else
      collab_set.add(repository.owner_id)
    end

    collab_set
  end

  # For private repos, "collaborator" == `readable_by?`. Composing
  # `async_readable_by?` under `Promise.all` lets `Platform::Loaders::Ability`
  # batch up to BATCH_SIZE (200) actors into a single Ability query,
  # vs. O(N) queries from synchronous per-user calls. Same idiom as
  # `HydroCorrectStargazersRepositoryTransferredJob`.
  sig { params(repository: Repository, user_ids: T::Array[Integer]).returns(T::Set[Integer]) }
  def collaborator_user_ids_for_private_repo(repository, user_ids)
    users = User.where(id: user_ids).index_by(&:id)
    promises = user_ids.filter_map do |uid|
      user = users[uid]
      next unless user
      repository.async_readable_by?(user).then { |readable| uid if readable }
    end
    Promise.all(promises).sync.compact.to_set
  end

  sig { returns(Integer) }
  def load_cursor
    Notifications::KV.store.get(CURSOR_KEY).value { "0" }.to_i
  end

  sig { params(cursor_id: Integer).void }
  def save_cursor(cursor_id)
    with_write { Notifications::KV.store.set(CURSOR_KEY, cursor_id.to_s) }
  end

  sig { void }
  def reset_cursor
    save_cursor(0)
  end

  sig do
    params(
      cursor_id: Integer,
      upper: Integer,
      cutoff: ActiveSupport::TimeWithZone,
      window_start: ActiveSupport::TimeWithZone,
    ).returns(T::Array[Repository])
  end
  def build_repository_query(cursor_id, upper, cutoff, window_start)
    Repository
      .where("id > ?", cursor_id)
      .where("id <= ?", upper)
      .where.not(archived_at: nil)
      .where("archived_at < ?", cutoff)
      .where("archived_at >= ?", window_start)
      .order(:id)
      .limit(REPO_BATCH_SIZE)
      .to_a
  end
end
