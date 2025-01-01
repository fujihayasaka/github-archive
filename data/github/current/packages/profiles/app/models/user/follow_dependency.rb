# typed: false
# frozen_string_literal: true

module User::FollowDependency
  extend ActiveSupport::Concern

  # Public: How long should we wait before updating a user's follower and following counts after
  # they change. A user's counts will only be updated at most one time in this many seconds.
  FOLLOW_CALCULATION_INTERVAL_IN_SECONDS = 10.minutes.in_seconds

  included do
    has_many :followings

    # If possible, use `#following_for_viewer` instead
    has_many :following,
      -> { order(:id) },
      through: :followings do
        def not_spammy_for(viewer:)
          merge(Following.filter_spam_for(viewer, foreign_key: :following_id))
        end
      end

    # rubocop:todo Rails/InverseOf
    has_many :followeds,
      class_name: "Following", foreign_key: "following_id"
    # rubocop:enable Rails/InverseOf

    # If possible, use `#followers_for_viewer` instead
    has_many :followers,
      -> { order(:id) },
      through: :followeds, source: :user do
        def not_spammy_for(viewer:)
          merge(Following.filter_spam_for(viewer))
        end
      end

    scope :following_starred, lambda { |user_id, repository_id, period = nil|
      since = period ? Star.timestamp_for_period(period) : 5.years.ago
      sql_user_id_stars = Arel.sql <<-'SQL', since: since, repository_id: repository_id
        SELECT stars.user_id
        FROM stars
        WHERE starrable_id = :repository_id
        AND starrable_type = 'Repository'
        AND stars.created_at > :since
        order by created_at DESC
      SQL

      star_users_ids = self.connection.select_rows(sql_user_id_stars)
      following_ids = Following.where(user_id: [user_id]).pluck(:following_id)
      user_ids = star_users_ids.flatten & following_ids
      User.default_scoped.where(id: user_ids).order("users.login ASC")
    }

    # Use this when you're rendering a list of users
    # with follow/unfollow buttons to avoid N+1s.
    #
    # Example:
    #   # Controller:
    #   GitHub::PrefillAssociations.prefill_batch_method(users, :followed_by?, current_user)
    #
    #   # View:
    #   users.each do |user|
    #     # this calls user.followed_by?(current_user)
    #     follow_button user
    #   end
    batch_method :followed_by? do |potential_followees, current_user|
      next Hash.new(false) unless current_user

      users_by_id = potential_followees.index_by(&:id)
      user_ids = users_by_id.keys

      User.bulk_following_check(current_user.id, user_ids).transform_keys do |user_id|
        users_by_id[user_id]
      end
    end
  end

  class_methods do
    # Public: Checks if the given User IDs can be followed by the user.
    #
    # user_id - User ID of the potential follower.
    # user_ids - Array of User IDs to check.
    #
    # Returns a hash dedicating whether each user can be followed: user_id => Boolean
    def bulk_can_follow_check(user_id, user_ids)
      return Hash.new if user_ids.blank?

      sql_bindings = {
        user_id: user_id,
        user_ids: user_ids,
      }

      sql = Arel.sql <<-SQL, **sql_bindings
        SELECT users.id, users.type, ignored_users.ignored_id
          FROM users
          LEFT OUTER JOIN ignored_users ON
            (users.id = ignored_users.ignored_id AND ignored_users.user_id = :user_id)
            OR (users.id = ignored_users.user_id AND ignored_users.ignored_id = :user_id)
          WHERE users.id IN (:user_ids)
          AND users.private_profile = 0
      SQL

      can_follow_checks = Hash[user_ids.map { |uid| [uid, false] }]
      self.find_by_sql(sql).each do |user|
        can_be_followed = !user.ignored_id.present? && user.id != user_id && (user.user? || user.organization?)
        can_follow_checks[user.id] = can_be_followed
      end
      can_follow_checks
    end

    # Public: Checks if the given User IDs are followed by the user.
    #
    # user_id - User ID of the follower.
    # user_ids - Array of User IDs to check.
    #
    # Returns a hash indicating whether each user is followed: user_id => Boolean
    def bulk_following_check(user_id, user_ids)
      return Hash.new if user_ids.blank?

      following_checks = Hash[user_ids.map { |uid| [uid, false] }]

      # You can't follow yourself, so let's not query for it
      potential_followee_ids = user_ids.without(user_id)

      Following.where(user_id: user_id, following_id: potential_followee_ids).pluck(:following_id).each do |following_id|
        following_checks[following_id] = true
      end
      following_checks
    end
  end

  # Public: Follow a user. You can try to follow a user multiple times without negative side
  # effects.
  #
  # user - the User to follow
  # context - string representing the context in which the follow event was triggered, e.g.,
  #           "api", "user_profile"
  #
  # Returns a Boolean indicating whether the follow worked or not. False means you are already
  # following the user, you have reached the rate limit for following users, or you're not allowed
  # to follow that particular user.
  def follow(user, context: "other")
    unblock(user) if blocking?(user)

    return false if user.followed_by?(self)
    return false unless can_follow?(user)

    following << user
    user.calculate_followerings_count(cascade: false)
    calculate_followerings_count(cascade: false)
    user.clear_preloaded_batch_method_value(:followed_by?, self)

    true
  end

  # Public: Stop following a user.
  #
  # user - the User to stop following
  # context - string representing the context in which the unfollow event was triggered, e.g.,
  #           "api", "user_profile"
  #
  # Returns truthy indicating if unfollow succeeded or not.
  def unfollow(user, context: "other")
    if user.followed_by?(self) && user != self
      following.destroy(user)
      user.calculate_followerings_count(cascade: false)
      calculate_followerings_count(cascade: false)
      user.clear_preloaded_batch_method_value(:followed_by?, self)
      invalidate_feed_cache
      true
    end
  end

  # Public: Enqueue job to update follower and following counts for this user.
  #
  # cascade - Boolean indicating whether the user's followers and followed users should also have
  #           their counts updated
  #
  # Returns a Boolean indicating if a new job was enqueued. A job will only be enqueued once
  # every ten minutes for this user.
  def calculate_followerings_count(cascade: true)
    CalculateFolloweringsCountJob.enqueue_once_per_interval(args: [id, cascade],
      interval: FOLLOW_CALCULATION_INTERVAL_IN_SECONDS)
  end

  def following_users_count
    return @following_users_count if defined?(@following_users_count)

    @following_users_count = following_for_viewer(nil).count
  end

  def can_follow?(user)
    return false if at_rate_limit?(user)

    can_follow = User.bulk_can_follow_check(id, [user.id])
    can_follow[user.id]
  end

  # nb. the follower/following methods are overridden
  # in Organization because orgs don't follow or have followers

  # Public: Total of users following this user
  #
  # Returns integer of cached followers count
  def followers_count(viewer:)
    count = if private_profile_for?(viewer) || spammy?
      0
    else
      Profiles::Kv.store.get("user.followers_count.#{id}").value { nil }
    end
    count ? count.to_i : followers_count!(sync_search_index: false)
  end

  # Public: Total of users this user follows
  #
  # Returns integer of cached following count
  def following_count(viewer:)
    count = if private_profile_for?(viewer) || spammy?
      0
    else
      Profiles::Kv.store.get("user.following_count.#{id}").value { nil }
    end

    count ? count.to_i : following_count!
  end

  # Public: Update and return cached count of followers
  #
  # This queries a count of non-spammy users that are following a given user.
  #
  # When a user is marked as spammy, all Following relationships where they are
  # the :user_id or :following_id will be marked as user_hidden.
  #
  # This means we can exclude those from the followers count without joining to
  # the users table and checking users.spammy.
  #
  # sync_search_index - override to avoid triggering AddToSearchIndexJob
  #                     when the caller is already an AddToSearchIndexJob!
  #
  # Returns Integer of followers count
  def followers_count!(sync_search_index: true)
    scope = followeds.not_spammy

    count = scope.count
    latest_count = Profiles::Kv.store.get("user.followers_count.#{id}").value { nil }
    if latest_count.nil? || latest_count.to_i != count
      ActiveRecord::Base.connected_to(role: :writing) do
        Profiles::Kv.store.set("user.followers_count.#{id}", count.to_s)
      end
    else
      ActiveRecord::Base.connected_to(role: :writing) do
        Profiles::Kv.store.set("user.followers_count.#{id}", count.to_s)
      end
    end

    # avoid cycle where AddToSearchIndexJob causes cache update
    # to GitHub.KV follower count which causes another job to queue!
    synchronize_search_index if sync_search_index
    count
  end

  # Public: Update and return cached count of users following
  #
  # This queries a count of non-spammy users that a given user is following.
  #
  # When a user is marked as spammy, all Following relationships where they are
  # the :user_id or :following_id will be marked as user_hidden.
  #
  # This means we can exclude those from the followers count without joining to
  # the users table and checking users.spammy.
  #
  # Returns Integer of following count
  def following_count!
    count = followings.not_spammy.count

    latest_count = Profiles::Kv.store.get("user.following_count.#{id}").value { nil }
    if latest_count.nil? || latest_count.to_i != count
      ActiveRecord::Base.connected_to(role: :writing) do
        Profiles::Kv.store.set("user.following_count.#{id}", count.to_s)
      end
    else
      ActiveRecord::Base.connected_to(role: :writing) do
        Profiles::Kv.store.set("user.following_count.#{id}", count.to_s)
      end
    end

    count
  end

  # Public: Return the count of followers that the viewer is allowed to see
  #
  # Count the number of followers for the user, taking into account whether the viewer is
  # allowed to see follows to or from a spammy user.
  #
  # This is intended to be an accurate representation of the number of total records that
  # followers_for_viewer will return, and can be used for pagination purposes as a more
  # efficient alternative to the default pagination behavior of calling
  # followers_for_viewer.count.
  #
  # If the viewer is a site admin, they're allowed to see the full list of followers.
  #
  # If the viewer is the user themselves, they're allowed to see all the non-spammy followers;
  # which means we need the join to users to filter out cases where the *other* user is spammy.
  #
  # For the common/other cases, we can count non-user-hidden records in the followers table directly.
  #
  # Returns an Integer count
  def followers_count_for_viewer(viewer)
    if viewer&.site_admin?
      followeds.count
    elsif spammy?
      return 0 unless viewer == self
      followers.not_spammy.count
    elsif private_profile_for?(viewer)
      0
    else
      scope = followeds.not_spammy

      scope.count
    end
  end

  # Public: Return followers that the viewer is allowed to see
  #
  # Returns a User relation
  def followers_for_viewer(viewer)
    if spammy? && !viewer&.site_admin?
      # This case shouldn't happen because spammy users should be hidden from other users,
      # but we can early return just to be safe.
      return User.none unless viewer == self

      # Spammy users need more complex queries to filter out follows where the *other* user is spammy
      #
      # followers.not_spammy applies the not_spammy scope to the users table
      followers.not_spammy.reorder("followers.user_id")
    elsif private_profile_for?(viewer)
      User.none
    else
      # If the viewer is staff or is spammy, we need to pass the viewer to not_spammy_for
      # to ensure the right spammy users are included; otherwise we can pass nil to
      # simplify the query.
      viewer = nil unless viewer&.spammy? || viewer&.site_admin?

      followers.not_spammy_for(viewer: viewer).reorder("followers.user_id")
    end
  end

  # Public: Return the count of followings that the viewer is allowed to see
  #
  # Count the number of followings for the user, taking into account whether the viewer is
  # allowed to see follows to or from a spammy user.
  #
  # This is intended to be an accurate representation of the number of total records that
  # followers_for_viewer will return, and can be used for pagination purposes as a more
  # efficient alternative to the default pagination behavior of calling
  # followers_for_viewer.count.
  #
  # If the viewer is a site admin, they're allowed to see the full list of followings.
  #
  # If the viewer is the user themselves, they're allowed to see all the non-spammy followings;
  # which means we need the join to users to filter out cases where the *other* user is spammy.
  #
  # For the common/other cases, we can count non-user-hidden records in the followers table directly.
  #
  # Returns an Integer count
  def following_count_for_viewer(viewer)
    if viewer&.site_admin?
      followings.count
    elsif spammy?
      return 0 unless viewer == self

      # Following is the has-many-through association that joins to users, which we need here
      # to filter out cases where the *other* user is spammy.
      following.not_spammy.count
    elsif private_profile_for?(viewer)
      0
    else

      # Followings is the has-many association for cases where user_id = this_user
      followings.not_spammy.count
    end
  end

  # Public: Return following users that the viewer is allowed to see
  #
  # Returns a User relation
  def following_for_viewer(viewer)
    if spammy? && !viewer&.site_admin?
      # This case shouldn't happen because spammy users should be hidden from other users,
      # but we can early return just to be safe.
      return User.none unless viewer == self

      # Spammy users need more complex queries to filter out follows where the *other* user is spammy
      #
      # following.not_spammy applies the not_spammy scope to the users table
      following.not_spammy.reorder("followers.user_id")
    elsif private_profile_for?(viewer)
      User.none
    else
      # If the viewer is staff or is spammy, we need to pass the viewer to not_spammy_for
      # to ensure the right spammy users are included; otherwise we can pass nil to
      # simplify the query.
      viewer = nil unless viewer&.spammy? || viewer&.site_admin?

      # following.not_spammy_for applies the filter_spam_for scope to the followers table
      following.not_spammy_for(viewer: viewer).reorder("followers.following_id")
    end
  end

  private

  def invalidate_feed_cache
    Conduit::KVBackedCache.invalidate_for(self)
  end

  def at_rate_limit?(user)
    potential_following = Following.new(user: self, following: user)
    potential_following.creation_rate_limited?(skip_increment: true)
  end
end
