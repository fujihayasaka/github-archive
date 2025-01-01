# typed: strict
# frozen_string_literal: true

module Stars
  class Domain < GH::Domain::Base
    extend T::Sig

    # Returns the count of starred topics for the given user_id
    sig { params(user_id: Integer).returns(Integer).checked(:always).on_failure(:raise) }
    def user_starred_topics_count(user_id)
      T.let(Star.where(user_id: user_id, starrable_type: Star::STARRABLE_TYPE_TOPIC).count, Integer)
    end

    # Returns the ids of the topics that the user has starred
    sig { params(user_id: Integer).returns(T::Array[Integer]).checked(:always).on_failure(:raise) }
    def user_starred_topic_ids(user_id)
      T.let(Star.where(user_id: user_id, starrable_type: Star::STARRABLE_TYPE_TOPIC).pluck(:starrable_id), T::Array[Integer])
    end

    # Returns a boolean indicating if the user has starred any repositories
    sig { params(user_id: Integer).returns(T::Boolean).checked(:always).on_failure(:raise) }
    def user_any_starred_repositories?(user_id)
      Star.where(user_id: user_id, starrable_type: Star::STARRABLE_TYPE_REPOSITORY).any?
    end

    # Returns the count of starred repositories for the given user_id
    sig { params(user_id: Integer).returns(Integer).checked(:always).on_failure(:raise) }
    def user_starred_repositories_count(user_id)
      T.let(Star.where(user_id: user_id, starrable_type: Star::STARRABLE_TYPE_REPOSITORY).count, Integer)
    end

    # Returns the ids of the repositories that the user has starred
    sig do
      params(
        user_id: Integer,
        repo_ids: T::Array[Integer],
        limit: T.nilable(Integer)
      ).returns(T::Array[Integer]).checked(:always).on_failure(:raise)
    end
    def user_starred_repository_ids(user_id, repo_ids: [], limit: nil)
      scope = Star.where(user_id: user_id, starrable_type: Star::STARRABLE_TYPE_REPOSITORY)
      scope = scope.where(starrable_id: repo_ids) if repo_ids.any?
      scope = scope.order(:id).limit(limit) if limit
      T.let(scope.pluck(:starrable_id), T::Array[Integer])
    end

    # Returns the ids of the repositories that the user has starred
    sig { params(user_id: Integer, limit: Integer).returns(T::Array[Integer]).checked(:always).on_failure(:raise) }
    def user_most_recently_starred_repo_ids(user_id, limit)
      Star.where(user_id: user_id, starrable_type: Star::STARRABLE_TYPE_REPOSITORY).
        order(created_at: :desc).
        limit(limit).
        pluck(:starrable_id)
    end

    # Returns the ids of the users who starred the repository
    sig { params(repo_id: Integer, since: Time).returns(T::Array[Integer]).checked(:always).on_failure(:raise) }
    def repo_starred_user_ids(repo_id, since:)
      star_users_ids = Star.where(starrable_id: repo_id, starrable_type: Star::STARRABLE_TYPE_REPOSITORY).
        where("created_at > ?", since).
        order(created_at: :desc).
        pluck(:user_id)
      T.let(star_users_ids, T::Array[Integer])
    end

    # Public: Star a repo for a user.
    sig do
      params(
        user: User,
        actor: GH::Auth::Actor,
        repository: Repository,
        context: String
      ).returns(GH::Result[StarEntity])
      .checked(:always).on_failure(:raise)
    end
    def star_repository(user:, actor:, repository:, context: "other")
      return GH::Result::Error.new("user cannot star") unless user_can_star?(user:, entity: repository)

      Stars::Creation.new(user:, actor:, entity: repository, context:).execute
    end

    # Public: Star a gist for a user.
    sig do
      params(
        user: User,
        actor: GH::Auth::Actor,
        gist: Gist,
        context: String
      ).returns(GH::Result[StarEntity])
      .checked(:always).on_failure(:raise)
    end
    def star_gist(user:, actor:, gist:, context: "other")
      return GH::Result::Error.new("user cannot star") unless user_can_star?(user:, entity: gist)

      Stars::Creation.new(user:, actor:, entity: gist, context:).execute
    end

    # Public: Star a topic for a user.
    sig do
      params(
        user: User,
        actor: GH::Auth::Actor,
        topic: Topic,
        context: String
      ).returns(GH::Result[StarEntity])
      .checked(:always).on_failure(:raise)
    end
    def star_topic(user:, actor:, topic:, context: "other")
      Stars::Creation.new(user:, actor:, entity: topic, context:).execute
    end

    # Public: can the user star this entity?
    #
    # entity - The entity to be potentially starred
    # is_readable - (optional) boolean we can pass to avoid re-checking
    #               readability of this entity by this user
    # is_starred - (optional) boolean to avoid re-checking whether the
    #              user has already starred the entity
    sig do
      params(
        user: User,
        entity: Stars::StarrableEntityTypes,
        is_readable: T.nilable(T::Boolean),
        is_starred: T.nilable(T::Boolean)
      ).returns(T::Boolean)
      .checked(:always).on_failure(:raise)
    end
    def user_can_star?(user:, entity:, is_readable: nil, is_starred: nil)
      return false if is_readable == false || is_starred

      if is_readable.nil?
        is_readable = !user.send(:unreadable?, entity)
        return false unless is_readable
      end

      if is_starred.nil?
        is_starred = entity.starred_by?(user)
        return false if is_starred
      end

      authorization = ContentAuthorizer.authorize(user, :star, :create, starrable: entity)
      authorization.passed?
    end

    sig { returns(Symbol) }
    attr_reader :caller_service
  end
end
