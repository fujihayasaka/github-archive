# typed: true
# frozen_string_literal: true

class User::InteractionAbility
  include Instrumentation::Model
  extend Scientist

  attr_reader :user

  TTL = 1.day

  # Public: Determine whether the user is allowed to make comments on public repos
  #
  # user - the User who would be performing interactions
  # repository - (optional) the Repository against which interactions would be performed
  # user_can_push - (optional) a Boolean to avoid duplicate pushable_by? checks
  #                 if it's already been calculated for this repository
  def self.interaction_allowed?(user:, repository: nil, user_can_push: nil)
    async_interaction_allowed?(user: user, repository: repository, user_can_push: user_can_push).sync
  end

  def self.async_interaction_allowed?(user:, repository: nil, user_can_push: nil)
    return Promise.resolve(false) unless user.present?

    return new(user).async_interactions_allowed? unless repository.present?

    pushable_promise =
      if user_can_push.nil?
        repository.async_pushable_by?(user)
      else
        Promise.resolve(user_can_push)
      end

    pushable_promise.then do |pushable|
      next true if pushable

      RepositoryInteractionAbility.async_interaction_allowed?(
        repository: repository,
        user: user,
      ).then do |allowed|
        next false unless allowed
        new(user).async_interactions_allowed?
      end
    end
  end

  # Allow the user to make interactions on public repos
  def self.allow_interactions(user)
    new(user).allow_interactions
  end

  # Prevent the user from interactioning on public repos
  def self.disallow_interactions(user)
    new(user).disallow_interactions
  end

  def self.toggle_interaction_ban(user)
    new(user).toggle_interaction_ban
  end

  # Get the expiration date of the ban
  def self.ban_expiry(user)
    new(user).ban_expiry
  end

  def initialize(user)
    @user = user
  end

  def allow_interactions
    instrument_update("allow", user.id)

    GitHub.dogstats.increment("user_interaction_limit.allow_interactions")
    user.allow_user_interactions
    user.reset_user_interaction_limit
  end

  def disallow_interactions
    instrument_update("disallow", user.id)

    expires_at = TTL.from_now

    GitHub.dogstats.increment("user_interaction_limit.disallow_interactions")
    user.disallow_user_interactions(expires_at: expires_at)
    user.reset_user_interaction_limit
  end

  def interactions_allowed?
    async_interactions_allowed?.sync
  end

  def async_interactions_allowed?
    return Promise.resolve(true) unless GitHub.interaction_limits_enabled? && user.present?

    GitHub.dogstats.increment("user_interaction_limit.check_interactions_allowed")

    user.async_user_interaction_limit.then do |limit|
      next true unless limit

      GitHub.dogstats.increment("user_interaction_limit.interactions_disallowed")
      false
    end
  end

  def toggle_interaction_ban
    interactions_allowed? ? disallow_interactions : allow_interactions
  end

  def ban_expiry
    user&.user_interaction_limit&.expiry
  end

  private

  def event_prefix
    "stafftools_interaction_ability"
  end

  def instrument_update(toggle_type, user_id)
    instrument toggle_type, user_id: user_id
  end
end
