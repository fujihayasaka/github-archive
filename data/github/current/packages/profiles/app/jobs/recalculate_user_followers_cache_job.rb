# typed: strict
# frozen_string_literal: true

# This Job will recalculate the followers counter cache for a provided list of User IDs.
class RecalculateUserFollowersCacheJob < ApplicationJob
  queue_as :recalculate_user_followers_cache

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  sig { params(user_ids: T::Array[Integer]).void }
  def perform(user_ids:)
    users = User.where(id: user_ids)

    users.each do |user|
      Profiles::Kv::DataStore.throttle_writes_with_retry { user.followers_count! }
    end
  end
end
