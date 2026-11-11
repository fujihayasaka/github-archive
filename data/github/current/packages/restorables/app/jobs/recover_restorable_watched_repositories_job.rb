# typed: strict
# frozen_string_literal: true

class RecoverRestorableWatchedRepositoriesJob < ApplicationJob
  include RestorableRecoveryJob

  queue_as :recover_restorable_watched_repositories

  retry_on_dirty_exit

  READ_BATCH_SIZE = 1000
  WRITE_BATCH_SIZE = 100

  sig { params(restorable_id: Integer, user_id: T.nilable(Integer)).void }
  def perform(restorable_id:, user_id: nil)
    restorable = load_restorable(restorable_id, [:restorable_watched_repositories])
    return unless restorable

    user = User.find_by(id: user_id) if user_id

    batch = restorable.watched_repositories.order(id: :asc).limit(READ_BATCH_SIZE)
    GitHub::PrefillAssociations.prefill_batch_method(batch, :repository)
    GitHub::PrefillAssociations.prefill_associations(batch, [:user], available_records: [user])
    GitHub::PrefillAssociations.prefill_associations(batch.map(&:repository), [:owner])

    batch.in_groups_of(WRITE_BATCH_SIZE, false) do |group|
      process_watched_repositories_batch(group, user)
    end

    if batch.size == READ_BATCH_SIZE
      self.class.perform_later(restorable_id: restorable_id, user_id: user&.id)
    else
      with_write { restorable.restored(:restorable_watched_repositories) }
    end
  end

  private

  sig { params(group: T::Array[Restorable::WatchedRepository], fallback_user: T.nilable(User)).void }
  def process_watched_repositories_batch(group, fallback_user)
    # Check validitity of users once per unique user
    users = (group.filter_map(&:user) + [fallback_user].compact).uniq
    skip_users = users_to_skip(users)

    group.each do |restorable_watched_repo|
      watching_user = restorable_watched_repo.user || fallback_user
      next if watching_user.nil?
      next if skip_users.include?(watching_user)

      repository = restorable_watched_repo.repository
      next if repository.nil?
      next if forbid_subscription?(watching_user, repository)
      next if user_already_subscribed?(watching_user, repository)
      next if GitHub.newsies.subscription_limit_exceeded?(watching_user, repository).value

      restore_subscription(watching_user, repository, restorable_watched_repo)
    end

    # Delete the processed batch
    Restorable::WatchedRepository.throttle do
      with_write { group.each(&:destroy!) }
    end
  end

  sig { params(user: User, repository: Repository, restorable_watched_repo: Restorable::WatchedRepository).void }
  def restore_subscription(user, repository, restorable_watched_repo)
    if restorable_watched_repo.ignored?
      Newsies::ListSubscription.throttle_writes do
        GitHub.newsies.ignore_list(user, repository)
      end
    else
      Newsies::ListSubscription.throttle_writes do
        GitHub.newsies.subscribe_to_list(user, repository)
      end
    end
  end
end
