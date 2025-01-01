# typed: strict
# frozen_string_literal: true

module Stars
  class Domain < GH::Domain::Base
    # Is the entity a starrable type?
    sig { params(class_name: String).returns(T::Boolean).checked(:always).on_failure(:raise) }
    def starrable?(class_name)
      Star::STARRABLE_TYPES.include?(class_name)
    end

    # Returns the count of starred objects for the given user_id
    sig { params(user_id: Integer).returns(Integer).checked(:always).on_failure(:raise) }
    def user_starred_objects_count(user_id)
      T.let(Star.where(user_id: user_id).count, Integer)
    end

    # Returns the count of starred topics for the given user_id
    sig { params(user_id: Integer).returns(Integer).checked(:always).on_failure(:raise) }
    def user_starred_topics_count(user_id)
      T.let(Star.where(user_id: user_id, starrable_type: Star::STARRABLE_TYPE_TOPIC).count, Integer)
    end

    # Count how many non-spammy users have starred this topic
    sig { params(topic_id: Integer).returns(Integer).checked(:always).on_failure(:raise) }
    def topic_star_count(topic_id)
      ActiveRecord::Base.connected_to(role: :reading) do
        T.let(Star.for_topic(topic_id).not_spammy.count, Integer)
      end
    end

    sig { void.checked(:always).on_failure(:raise) }
    private def reset_topic_starred_by_user_cache
      @topic_starred_by_user_cache = T.let(nil, T.nilable(T::Hash[[Integer, Integer], T::Boolean]))
    end

    sig { returns(T::Hash[[Integer, Integer], T::Boolean]) }
    private def topic_starred_by_user_cache
      return @topic_starred_by_user_cache if @topic_starred_by_user_cache

      @topic_starred_by_user_cache = T.must(T.let(Hash.new, T.nilable(T::Hash[[Integer, Integer], T::Boolean])))
    end

    # Returns true if the given user has starred the given topic
    sig { params(topic_id: Integer, user_id: Integer).returns(T::Boolean).checked(:always).on_failure(:raise) }
    def topic_starred_by_user?(topic_id, user_id)
      cache_key = [topic_id, user_id]
      return T.must(topic_starred_by_user_cache[cache_key]) if topic_starred_by_user_cache.key?(cache_key)

      result = Star.where(
        starrable_id: topic_id,
        starrable_type: Star::STARRABLE_TYPE_TOPIC,
        user_id: user_id
      ).exists?

      topic_starred_by_user_cache[cache_key] = result
    end

    # Count how many non-spammy users have starred this repository
    sig { params(repository_id: Integer).returns(Integer).checked(:always).on_failure(:raise) }
    def repository_star_count(repository_id)
      ActiveRecord::Base.connected_to(role: :reading) do
        T.let(Star.for_repository(repository_id).not_spammy.count, Integer)
      end
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
      scope = user_stars_scope(
        user_id,
        starrable_type: Star::STARRABLE_TYPE_REPOSITORY,
        starrable_ids: repo_ids,
        limit: limit,
      )
      T.let(scope.pluck(:starrable_id), T::Array[Integer])
    end

    # Returns full StarEntities for the repositories that a user has starred
    sig do
      params(
        user_id: Integer,
        repo_ids: T::Array[Integer],
        limit: T.nilable(Integer)
      ).returns(GH::Domain::Collection[StarEntity]).checked(:always).on_failure(:raise)
    end
    def user_repository_stars(user_id, repo_ids: [], limit: nil)
      scope = user_stars_scope(
        user_id,
        starrable_type: Star::STARRABLE_TYPE_REPOSITORY,
        starrable_ids: repo_ids,
        limit: limit,
      )
      GH::Domain::Collection.new(scope.to_a)
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

    # Returns the ids of the users who starred the gist
    sig { params(gist_id: Integer).returns(T::Array[Integer]).checked(:always).on_failure(:raise) }
    def gist_starred_user_ids(gist_id)
      star_users_ids = GistStar.where(gist_id: gist_id).
        order(created_at: :asc).
        pluck(:user_id)
      T.let(star_users_ids, T::Array[Integer])
    end

    sig { void.checked(:always).on_failure(:raise) }
    private def reset_gist_starred_by_user_cache
      @gist_starred_by_user_cache = T.let(nil, T.nilable(T::Hash[[Integer, Integer], T::Boolean]))
    end

    sig { returns(T::Hash[[Integer, Integer], T::Boolean]) }
    private def gist_starred_by_user_cache
      return @gist_starred_by_user_cache if @gist_starred_by_user_cache

      @gist_starred_by_user_cache = T.must(T.let(Hash.new, T.nilable(T::Hash[[Integer, Integer], T::Boolean])))
    end

    # Returns true if the given user has starred the given gist
    sig { params(gist_id: Integer, user_id: Integer).returns(T::Boolean).checked(:always).on_failure(:raise) }
    def gist_starred_by_user?(gist_id, user_id)
      cache_key = [gist_id, user_id]
      return T.must(gist_starred_by_user_cache[cache_key]) if gist_starred_by_user_cache.key?(cache_key)

      result = GistStar.where(
        gist_id: gist_id,
        user_id: user_id
      ).exists?

      gist_starred_by_user_cache[cache_key] = result
    end

    sig { void.checked(:always).on_failure(:raise) }
    private def reset_repo_starred_by_user_cache
      @repo_starred_by_user_cache = T.let(nil, T.nilable(T::Hash[[Integer, Integer], T::Boolean]))
    end

    sig { returns(T::Hash[[Integer, Integer], T::Boolean]) }
    private def repo_starred_by_user_cache
      return @repo_starred_by_user_cache if @repo_starred_by_user_cache

      @repo_starred_by_user_cache = T.must(T.let(Hash.new, T.nilable(T::Hash[[Integer, Integer], T::Boolean])))
    end

    # Returns true if the given user has starred the given repositories
    sig { params(repo_ids: T::Array[Integer], user_id: Integer).returns(T::Hash[Integer, T::Boolean]).checked(:always).on_failure(:raise) }
    def repos_starred_by_user?(repo_ids, user_id)
      starred_repo_ids = Star.where(
        starrable_id: repo_ids,
        starrable_type: Star::STARRABLE_TYPE_REPOSITORY,
        user_id: user_id
      ).pluck(:starrable_id).to_set

      repo_ids.each_with_object(T.let(Hash.new, T::Hash[Integer, T::Boolean])) do |repo_id, result|
        repo_starred = starred_repo_ids.include?(repo_id)

        repo_starred_by_user_cache[[repo_id, user_id]] = repo_starred
        result[repo_id] = repo_starred
      end
    end

    # Precache the results of whether the given user has starred the given repositories to avoid N+1 queries
    sig { params(repo_ids: T::Array[Integer], user_id: Integer).void.checked(:always).on_failure(:raise) }
    def precache_repos_starred_by_user?(repo_ids, user_id)
      repos_starred_by_user?(repo_ids, user_id)
    end

    # Precache user stars for the given topic ids
    sig { params(topic_ids: T::Array[Integer], user_id: Integer).void.checked(:always).on_failure(:raise) }
    def precache_topics_starred_by_user?(topic_ids, user_id)
      starred_topic_ids = Star.where(
        starrable_id: topic_ids,
        starrable_type: Star::STARRABLE_TYPE_TOPIC,
        user_id: user_id
      ).pluck(:starrable_id)

      topic_ids.each_with_object(T.let(Hash.new, T::Hash[Integer, T::Boolean])) do |topic_id, result|
        topic_starred = starred_topic_ids.include?(topic_id)

        topic_starred_by_user_cache[[topic_id, user_id]] = topic_starred
        result[topic_id] = topic_starred
      end
    end

    # Returns true if the given user has starred the given repository
    sig { params(repo_id: Integer, user_id: Integer).returns(T::Boolean).checked(:always).on_failure(:raise) }
    def repo_starred_by_user?(repo_id, user_id)
      cache_key = [repo_id, user_id]
      return T.must(repo_starred_by_user_cache[cache_key]) if repo_starred_by_user_cache.key?(cache_key)

      result = Star.where(
        starrable_id: repo_id,
        starrable_type: Star::STARRABLE_TYPE_REPOSITORY,
        user_id: user_id
      ).exists?

      repo_starred_by_user_cache[cache_key] = result
    end

    # Returns a paginated collection of stars for the given repository non-spammy for the given viewer
    sig do
      params(
        repo_id: Integer,
        viewer: T.nilable(User),
        pagination: GH::Pagination::Base,
        sorts: T::Array[GH::Pagination::Sort],
      ).returns(GH::Domain::Collection[StarEntity]).checked(:always).on_failure(:raise)
    end
    def repo_stars_not_spammy_for_viewer(repo_id, viewer:, pagination:, sorts: [GH::Pagination::Sort.new(field: "created_at", direction: GH::Pagination::Sort::Direction::ASC)])
      scope = if viewer.present?
        Star.force_index(:index_stars_on_starrable_id_type_created_user_hidden)
      else
        Star
      end

      scope = scope.for_repository(repo_id).filter_spam_for(viewer).order(GH::Pagination::Sort.to_order_by(sorts:))

      result = GH::Pagination::Paginator.paginate(
        scope:,
        pagination:,
        sorts:,
        lazy_total_entries: -> { scope.count },
      )

      result
    end

    # Returns a paginated collection of stars for the given topic non-spammy for the given viewer
    sig do
      params(
        topic_id: Integer,
        viewer: T.nilable(User),
        pagination: GH::Pagination::Base,
        sorts: T::Array[GH::Pagination::Sort],
      ).returns(GH::Domain::Collection[StarEntity]).checked(:always).on_failure(:raise)
    end
    def topic_stars_not_spammy_for_viewer(topic_id, viewer:, pagination:, sorts: [GH::Pagination::Sort.new(field: "created_at", direction: GH::Pagination::Sort::Direction::ASC)])
      scope = if viewer.present?
        Star.force_index(:index_stars_on_starrable_id_type_created_user_hidden)
      else
        Star
      end

      scope = scope.for_topic(topic_id).filter_spam_for(viewer).order(GH::Pagination::Sort.to_order_by(sorts:))

      result = GH::Pagination::Paginator.paginate(
        scope:,
        pagination:,
        sorts:,
        lazy_total_entries: -> { scope.count },
      )

      result
    end

    # Returns a paginated collection of stars for the given gist non-spammy for the given viewer
    sig do
      params(
        gist_id: Integer,
        viewer: T.nilable(User),
        pagination: GH::Pagination::Base,
        sorts: T::Array[GH::Pagination::Sort],
      ).returns(GH::Domain::Collection[StarEntity]).checked(:always).on_failure(:raise)
    end
    def gist_stars_not_spammy_for_viewer(gist_id, viewer:, pagination:, sorts: [GH::Pagination::Sort.new(field: "created_at", direction: GH::Pagination::Sort::Direction::ASC)])
      scope = GistStar.where(gist_id:).filter_spam_for(viewer).order(GH::Pagination::Sort.to_order_by(sorts:))

      result = GH::Pagination::Paginator.paginate(
        scope:,
        pagination:,
        sorts:,
        lazy_total_entries: -> { scope.count },
      )

      result
    end

    # Resets the in-memory caches of the domain instance
    sig { returns(T.self_type).checked(:always).on_failure(:raise) }
    def reset_caches
      reset_repo_starred_by_user_cache
      reset_gist_starred_by_user_cache
      reset_topic_starred_by_user_cache

      self
    end

    # Public: Star a repo for a user.
    sig do
      params(
        user: User,
        repository: Repository,
        context: String,
        created_at: T.nilable(Time)
      ).returns(T.any(GH::Result::Ok[StarEntity], GH::Result::Error::ContentAuthorizationError[ContentAuthorizer], GH::Result::Error[String]))
      .checked(:always).on_failure(:raise)
    end
    def star_repository(user:, repository:, context: "other", created_at: nil)
      can_star_result = user_can_star_detail(user:, entity: repository)
      unless can_star_result.ok?
        return T.cast(can_star_result, T.any(GH::Result::Error::ContentAuthorizationError[ContentAuthorizer], GH::Result::Error[String]))
      end

      result = Stars::Creation.new(user:, entity: repository, context:, created_at:).call
      if result.ok?
        repo_starred_by_user_cache[[repository.id, user.id]] = true
      end

      result
    end

    # Public: Star a gist for a user.
    sig do
      params(
        user: User,
        gist: Gist,
        context: String
      ).returns(T.any(GH::Result::Ok[StarEntity], GH::Result::Error::ContentAuthorizationError[ContentAuthorizer], GH::Result::Error[String]))
      .checked(:always).on_failure(:raise)
    end
    def star_gist(user:, gist:, context: "other")
      can_star_result = user_can_star_detail(user:, entity: gist)
      unless can_star_result.ok?
        return T.cast(can_star_result, T.any(GH::Result::Error::ContentAuthorizationError[ContentAuthorizer], GH::Result::Error[String]))
      end

      result = Stars::Creation.new(user:, entity: gist, context:).call
      if result.ok?
        gist_starred_by_user_cache[[gist.id, user.id]] = true
      end

      result
    end

    # Public: Star a topic for a user.
    sig do
      params(
        user: User,
        topic: Topic,
        context: String
      ).returns(T.any(GH::Result::Ok[StarEntity], GH::Result::Error[String]))
      .checked(:always).on_failure(:raise)
    end
    def star_topic(user:, topic:, context: "other")
      result = Stars::Creation.new(user:, entity: topic, context:).call

      if result.ok?
        topic_starred_by_user_cache[[topic.id, user.id]] = true
      end

      result
    end

    # Public: Star topics for a user.
    sig do
      params(
        user: User,
        topics: T::Array[Topic],
        context: String
      ).returns(T::Array[T.any(GH::Result::Ok[StarEntity], GH::Result::Error[String])])
      .checked(:always).on_failure(:raise)
    end
    def star_topics(user:, topics:, context: "other")
      topics.map do |topic|
        result = Stars::Creation.new(user:, entity: topic, context:).call

        if result.ok?
          topic_starred_by_user_cache[[topic.id, user.id]] = true
        end

        result
      end
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
      user_can_star_detail(user:, entity:, is_readable:, is_starred:).ok?
    end

    # Public: Returns the amount of stars that a repository has obtained since
    # the given time period. Default time period is the last day.
    sig { params(repository_id: Integer, period: Symbol).returns(Integer) }
    def repository_stars_since(repository_id:, period: :daily)
      StarsSince.repository(repository_id:, period:)
    end

    # Public: Returns the amount of stars that a list of repositories have obtained since
    # the given time period. Default time period is the last day.
    sig { params(repository_ids: T::Array[Integer], period: Symbol).returns(T::Hash[Integer, Integer]) }
    def repositories_stars_since(repository_ids:, period: :daily)
      raise ArgumentError, "Too many repository_ids" if repository_ids.size > 100

      StarsSince.repositories(repository_ids:, period:)
    end

    # Public: Returns the most recent star for a repository
    sig { params(repository_id: Integer).returns(T.nilable(StarEntity)) }
    def repository_latest_star(repository_id)
      star = Star.for_repository(repository_id).order(id: :asc).last
      StarEntity.new(**star.attributes) if star
    end

    # Public: Returns a star by its ID
    sig { params(star_id: Integer).returns(T.nilable(StarEntity)) }
    def by_id(star_id)
      return nil if star_id <= 0

      star = Star.find_by(id: star_id)
      StarEntity.new(**star.attributes) if star
    end

    # Public: Returns a collection of stars, by their IDs
    sig { params(star_ids: T::Array[Integer]).returns(GH::Domain::Collection[StarEntity]) }
    def by_ids(star_ids)
      scope = Star.where(id: star_ids).to_a
      GH::Domain::Collection.new(scope)
    end

    private

    sig do
      params(
        user: User,
        entity: Stars::StarrableEntityTypes,
        is_readable: T.nilable(T::Boolean),
        is_starred: T.nilable(T::Boolean)
      ).returns(T.any(GH::Result[::ContentAuthorizer], GH::Result::Error[String]))
      .checked(:always).on_failure(:raise)
    end
    def user_can_star_detail(user:, entity:, is_readable: nil, is_starred: nil)
      return GH::Result::Error.new("user cannot star") if is_readable == false || is_starred

      if is_readable.nil?
        is_readable = !user.send(:unreadable?, entity)
        return GH::Result::Error.new("user cannot star") unless is_readable
      end

      if is_starred.nil?
        user_id = user.id
        entity_id = entity.id
        is_starred = case entity
        when Repository
          repo_starred_by_user?(entity_id, user_id)
        when Gist
          gist_starred_by_user?(entity_id, user_id)
        when Topic
          topic_starred_by_user?(entity_id, user_id)
        end
        return GH::Result::Error::NotUnique.new("user already starred this entity") if is_starred
      end

      authorization = ContentAuthorizer.authorize(user, :star, :create, starrable: entity)
      if authorization.passed?
        GH::Result::Ok.new(authorization)
      else
        GH::Result::Error::ContentAuthorizationError.new(authorization)
      end
    end

    sig do
      params(
        user_id: Integer,
        starrable_type: String,
        starrable_ids: T::Array[Integer],
        limit: T.nilable(Integer),
      ).returns(ActiveRecord::Relation)
    end
    def user_stars_scope(user_id, starrable_type:, starrable_ids:, limit:)
      scope = Star.where(user_id: user_id, starrable_type: starrable_type)
      scope = scope.where(starrable_id: starrable_ids) if starrable_ids.any?
      scope = scope.order(:id).limit(limit) if limit
      scope
    end
  end
end
