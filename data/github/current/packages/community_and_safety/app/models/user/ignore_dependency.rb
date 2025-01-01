# typed: false
# frozen_string_literal: true

module User::IgnoreDependency
  extend ActiveSupport::Concern

  included do
    has_many :ignored_users
    has_many :ignored, class_name: "User", through: :ignored_users, foreign_key: :user_id
    has_many :ignored_by_users, class_name: "IgnoredUser", foreign_key: :ignored_id # rubocop:todo Rails/InverseOf
    has_many :ignored_by, class_name: "User", through: :ignored_by_users, foreign_key: :ignored_id

    # Filter users to just those who are blocking the specified user.
    #
    # user_or_id - a User or Integer User ID
    scope :blocking, -> (user_or_id) { where(id: IgnoredUser.blocking(user_or_id).select(:user_id)) }

    # Public: Filter users to just those who are spammy or are blocking the given user. Does not consider if the
    # viewer is staff or not when filtering based on spamminess. Will not include the viewer when they are spammy.
    #
    # viewer - a User or nil
    #
    # Returns an ActiveRecord::Relation of User.
    scope :spammy_or_blocking, ->(viewer) do
      if GitHub.spamminess_check_enabled?
        if viewer
          spammy.where.not(id: viewer).or(blocking(viewer))
        else
          spammy
        end
      elsif viewer
        blocking(viewer)
      else
        none
      end
    end

    # Public: Filter users to just those who are not blocking the given user.
    #
    # viewer - a User
    #
    # Returns an ActiveRecord::Relation of User.
    scope :not_blocking, ->(viewer) do
      if viewer
        blocking_user_ids = IgnoredUser.blocking(viewer).select(:user_id)
        where.not(id: blocking_user_ids)
      else
        scoped
      end
    end
  end

  # Public: Returns the list of ignored users sorted reverse chronologically
  # depending on when they were ignored.
  #
  # Returns a Relation
  def latest_ignored
    ignored.order("ignored_users.id DESC")
  end

  # Public: Returns a list of ignored users sorted by the expires at followed by
  # the rest, where those expiring sooner are at the top. It also filters out
  # those who are spammy.
  #
  # Returns a relation
  def sorted_ignored
    ignored_users.joins(:ignored).where(users: { spammy: false }).order(Arel.sql("-expires_at DESC"))
  end

  def permanent_ignored
    ignored_users.where(expires_at: nil)
  end

  # Public: Returns true if the user should avoid one or more of the users.
  # Users to avoid are those that are ignored or spammy.
  #
  # *users - One or more User objects to check.
  #
  # Returns true if any of the users should be avoided by this user.
  def avoid?(*users)
    avoidable_reason_for(*users).present?
  end

  # Public: Returns the reason that this user should avoid one of the given
  # users.
  #
  # *users - One or more User objects to check.
  #
  # Returns a Symbol reason or nil.
  def avoidable_reason_for(*users)
    return if users.blank?
    return :bad_actor  if users.any?(&:bad_actor?)
    return :ignore     if blocking?(*users)
    return :ignored_by if blocked_by?(*users)
  end

  # Flag to indicates if we should not trigger notifications system-wide
  # Currently true if the user is spammy or the account has been suspended
  def bad_actor?
    spammy? || suspended?
  end

  # Public: Blocks a given user.
  #
  # user - The User to block.
  # actor - The User initiating the block - defaults to self
  # duration - Int number of days for the block to last (for orgs only)
  # note - An optional note to add to the ignored_user record
  #
  # Returns <IgnoredUser> object if the User was added to the ignore list, or false.
  def block(
    user,
    actor: self,
    duration: nil,
    blocked_from_content: nil,
    send_notification: false,
    minimize_reason: nil,
    note: nil
  )
    expires_at = duration.days.from_now if duration

    IgnoredUser.create(
      ignored_by: self,
      ignored: user,
      actor: actor,
      expires_at: expires_at,
      blocked_from_content: blocked_from_content,
      send_notification: send_notification,
      minimize_reason: minimize_reason,
      note: note,
    )
  end

  # Deprecated: use User#block instead
  def ignore(user)
    block(user)
  end

  CanBlockResult = Struct.new(:blockable?, :reason)

  # Public: Can this User (or Org) block the specified user?
  # Users cannot block themselves or someone they are already blocking
  #
  # Returns a CanBlockResult containing Boolean result and String reason
  def can_block(user)
    ignored_user = IgnoredUser.new(ignored_by: self, ignored: user)
    CanBlockResult.new(ignored_user.valid?, ignored_user.errors.full_messages.join(", "))
  end

  # Public: Unblocks a user
  #
  # user - A User
  # actor - The User initiating the unblock - defaults to self
  #
  # Returns nothing.
  def unblock(user, actor: self)
    ignored_user = ignored_users.find_by(ignored: user)
    return unless ignored_user
    ignored_user.destroy(actor: actor)
  end

  # Deprecated: use User#unblock instead
  def unignore(user)
    unblock(user)
  end

  # Public: Checks if any of the given users are blocked by the current
  # user.
  #
  # *users - One or more Users or Integer User IDs to check.
  #
  # Returns true if any of the Users are blocked.
  def blocking?(*users)
    users.reject! { |user| user.nil? || user == self }
    return false if users.blank?
    ignored.exists?(id: users)
  end

  def async_blocking?(user)
    return Promise.resolve(false) unless user
    return Promise.resolve(false) if user == self

    Platform::Loaders::UserBlockedCheck.load(self.id, user.id)
  end

  # Public: Check if this user is blocking any of the given users or is being blocked by any of them.
  #
  # users - an array of User objects
  #
  # Returns a Hash where the keys are IDs of the given users and the values are Booleans indicating whether that
  # user is blocking or being blocked by this user.
  sig { params(users: T::Array[User]).returns(T::Hash[Integer, T::Boolean]) }
  def blocking_or_blocked_by?(users)
    return Hash.new(false) if new_record?
    return Hash.new(false) if users.empty?

    block_loader = Platform::Loaders::UserBlockedCheck.new
    other_users = users.compact.reject { |user| user.id == id }
    user_id_pairs = other_users.map { |user| [user.id, id] } + other_users.map { |user| [id, user.id] }
    blocks = block_loader.fetch(user_id_pairs)

    other_users.each_with_object(Hash.new { false }) do |other_user, hash|
      key1 = [other_user.id, id]
      key2 = [id, other_user.id]
      hash[other_user.id] = blocks.key?(key1) || blocks.key?(key2)
    end
  end

  # Deprecated: use User#blocking? instead
  def ignore?(*users)
    blocking?(*users)
  end

  # Public: Checks if the current User is blocked by any of the given users.
  #
  # *users - One or more Users or Integer User IDs to check.
  #
  # Returns true if any of the Users are blocked.
  def blocked_by?(*users)
    users.reject! { |user| user.nil? || user == self }
    return false if users.blank?
    ignored_by.exists?(id: users)
  end

  def async_blocked_by?(user)
    return Promise.resolve(false) unless user
    return Promise.resolve(false) if user == self

    Platform::Loaders::UserBlockedCheck.load(user.id, self.id)
  end

  # Deprecated: use User#blocked_by? instead
  def ignored_by?(*users)
    blocked_by?(*users)
  end

  # Public: Returns all User IDs that are ignored or ignore the current user.
  #
  # Returns an Array of Integer User IDs.
  def ignored_or_ignored_by_ids
    ignored_ids | ignored_by_ids
  end

  # Public: Finds which users in the given set are ignored by the current user.
  #
  # users - An Array of User instances or Integer User IDs.
  #
  # Returns an Array of Users.
  def ignoring_in(users)
    users.compact!
    return [] if users.blank?
    ignored.where(id: users).to_a
  end

  def ignored_by_any(users)
    users.compact!
    return [] if users.blank?
    ignored_by.where(id: users).to_a
  end

  # Completely resets the user's ignore list.
  def remove_ignore_list
    ignored.clear
  end

  # Public: Indicates if an actor can manage blocked users for this user.
  #
  # actor - The User to check permissions for.
  #
  # Returns a Boolean.
  def blocked_users_manageable_by?(actor)
    return true if adminable_by?(actor)
    return false unless organization?
    moderator?(actor)
  end

  # Public: Indicates if an actor can manage blocked users for this user.
  #
  # actor - The User to check permissions for.
  #
  # Returns a Promise<Boolean>.
  def async_blocked_users_manageable_by?(actor)
    async_adminable_by?(actor).then do |is_admin|
      next true if is_admin
      next false unless organization?
      async_moderator?(actor)
    end
  end
end
