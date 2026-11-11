# typed: strict
# frozen_string_literal: true

module RestorableRecoveryJob
  extend T::Helpers

  requires_ancestor { ApplicationJob }

  # Common functionality for filtering out users that should be skipped
  sig { params(users: T::Array[User]).returns(T::Set[User]) }
  def users_to_skip(users)
    users.select { |user| user.deleted? || user.spammy? || !user.user? }.to_set
  end

  # Determine if a user should be able to subscribe to a repository based on authorizations
  sig { params(user: User, repository: Repositories::IRepository).returns(T::Boolean) }
  def forbid_subscription?(user, repository)
    owner = repository.owner
    return true if owner.nil?
    return true if user.blocked_by?(owner)
    return true unless repository.public? || repository.resources.contents.readable_by?(user)

    false
  end

  # Common functionality for checking if a user is already subscribed to a repository
  sig { params(user: User, repository: Repositories::IRepository).returns(T::Boolean) }
  def user_already_subscribed?(user, repository)
    # Check notification_subscriptions and notification_thread_type_subscriptions
    watching_sub = GitHub.newsies.subscription_status(user, repository).value!
    return true if watching_sub.valid? || watching_sub.thread_types.any?

    # Check notification_thread_subscriptions
    repo_list = Newsies::List.to_object(repository)
    return true if Newsies::ThreadSubscription.for_user(user).for_list(repo_list).any?

    false
  end

  # Common functionality for loading and validating a restorable record
  sig { params(restorable_id: Integer, restoration_types: T::Array[Symbol]).returns(T.nilable(Restorable)) }
  def load_restorable(restorable_id, restoration_types)
    restorable = Restorable.find_by(id: restorable_id)
    return nil unless restorable&.restoring?(restoration_types)

    restorable
  end
end
