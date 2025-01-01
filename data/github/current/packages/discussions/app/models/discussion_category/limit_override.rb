# typed: true
# frozen_string_literal: true

class DiscussionCategory::LimitOverride
  extend T::Sig

  include ActiveModel::Validations

  # The allowed discussion category count specified for an override must always
  # be higher than the default maximum.
  MINIMUM_LIMIT = DiscussionCategory::MAX_CATEGORIES_PER_REPO + 1

  attr_reader :repository, :actor

  validates :repository, :actor, presence: true
  validate :ensure_actor_is_authorized

  # Public: Returns the override value if set for a specific repository.
  #
  # repository - The Repository to check the override for.
  #
  # Returns an Integer|nil.
  sig { params(repository: T.untyped).returns(T.untyped) }
  def self.for(repository)
    new(repository: repository, actor: nil).value
  end

  # repository - The Repository containing discussion categories.
  # actor      - The User who is setting the limit override.
  sig { params(repository: T.untyped, actor: T.untyped).void }
  def initialize(repository:, actor:)
    @repository = repository
    @actor      = actor
  end

  # Public: The current discussion category count limit, if an override
  #         has been set.
  #
  # Returns an Integer|nil.
  sig { returns(T.untyped) }
  def value
    return if repository.blank?

    value = Discussions::Kv.store.get(limit_key).value { nil }
    return if value.blank?

    value.to_i
  end

  # Public: Sets a new discussion category count limit override for a repository.
  #
  # limit - The Integer discussion category count that we want to allow.
  #
  # Returns a DiscussionCategory::LimitOverride::Result.
  sig { params(limit: T.untyped).returns(T.untyped) }
  def set(limit:)
    if limit.to_i < MINIMUM_LIMIT
      return Result.failure(
        repository: repository,
        errors: ["Limit must be at least #{MINIMUM_LIMIT}"],
      )
    end

    if valid?
      Discussions::Kv.store.set(limit_key, limit.to_s)
      Result.success(repository: repository)
    else
      Result.failure(repository: repository, errors: errors.full_messages)
    end
  end

  # Public: Deletes an existing discussion category count limit override for
  #         a repository.
  #
  # Returns a DiscussionCategory::LimitOverride::Result.
  sig { returns(T.untyped) }
  def delete
    if valid?
      Discussions::Kv.store.del(limit_key)
      Result.success(repository: repository)
    else
      Result.failure(repository: repository, errors: errors.full_messages)
    end
  end

  class Result
    extend T::Sig

    attr_reader :repository, :success, :errors
    alias_method :success?, :success

    # repository - the Repository that we are setting the category limit
    #              override for.
    # success    – a Boolean indicating the success of an operation.
    # errors     – an Array of String error messages.
    sig { params(repository: T.untyped, success: T.untyped, errors: T.untyped).void }
    def initialize(repository:, success:, errors:)
      @repository = repository
      @success    = success
      @errors     = errors
    end

    sig { params(repository: T.untyped).returns(T.untyped) }
    def self.success(repository:)
      new(success: true, repository: repository, errors: [])
    end

    sig { params(repository: T.untyped, errors: T.untyped).returns(T.untyped) }
    def self.failure(repository:, errors:)
      new(success: false, repository: repository, errors: errors)
    end
  end

  private

  def limit_key
    "repositories.#{repository.id}.discussion_categories.category_limit"
  end

  def ensure_actor_is_authorized
    unless actor&.site_admin?
      errors.add(:actor, "must be a site admin")
    end
  end
end
