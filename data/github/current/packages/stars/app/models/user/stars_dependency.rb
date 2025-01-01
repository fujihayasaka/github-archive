# typed: true
# frozen_string_literal: true

module User::StarsDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  include Stars::Domain::Provider

  requires_ancestor { User }

  # Public: can the user star this entity?
  #
  # entity - The entity to be potentially starred
  # is_readable - (optional) boolean we can pass to avoid re-checking
  #               readability of this entity by this user
  # is_starred - (optional) boolean to avoid re-checking whether the
  #              user has already starred the entity
  def can_star?(entity, is_readable: nil, is_starred: nil)
    return false if is_readable == false || is_starred

    if is_readable.nil?
      is_readable = !unreadable?(entity)
      return false unless is_readable
    end

    if is_starred.nil?
      is_starred = entity.starred_by?(self)
      return false if is_starred
    end

    authorization = ContentAuthorizer.authorize(self, :star, :create, starrable: entity)
    authorization.passed?
  end

  def async_can_star?(entity)
    promises = []
    promises << entity.async_owner if entity.respond_to?(:owner)
    promises << entity.async_parent if entity.respond_to?(:parent)
    Promise.all(promises).then do
      Promise.resolve(can_star?(entity))
    end
  end

  # Star an entity. You can star/unstar any entity you can see.
  #
  # entity - The Repository or Gist in question
  def star(entity, context: "other")
    return false unless can_star?(entity)

    Star.transaction do
      entity.transaction do
        entity.stars.create!(user: self, actor: self, hydro_context_type: context)
        entity.clear_preloaded_batch_method_value(:starred_by?, self)
      end
    end

    if entity.instance_of?(::Repository)
      GitHub.instrument "stars.update_count", user: self, starred_id: entity.id,
        starred_type: Star::STARRABLE_TYPE_REPOSITORY
    end

    true
  rescue ActiveRecord::RecordNotUnique
  end

  # Unstars an entity. You can star/unstar any entity you can see.
  #
  # entity - The Repository, Topic, or Gist in question
  #
  # Returns nothing.
  def unstar(entity, actor: self, context: "other")
    star_object = case entity
    when Repository, Topic
      stars.where(starrable: entity).first
    when Gist
      gist_stars.where(gist: entity).first
    else
      nil
    end

    return false unless star_object.present?

    Star.transaction do
      entity.transaction do
        star_object.actor = actor
        star_object.hydro_context_type = context
        star_object.destroy!
        entity.clear_preloaded_batch_method_value(:starred_by?, self)
      end
    end

    # Pass along the new star count without having to reload the record to get it from the database:
    if field_name = entity.stargazer_count_column
      entity[field_name] = star_object.starrable.stargazer_count
    end

    true
  rescue ActiveRecord::RecordNotDestroyed
    false
  end

  def any_starred_repositories?
    stars_domain.user_any_starred_repositories?(T.must(self.id))
  end

  def starred_repositories_count
    stars_domain.user_starred_repositories_count(T.must(self.id))
  end

  def starred_repository_ids(repo_ids: [], limit: nil)
    stars_domain.user_starred_repository_ids(T.must(self.id), repo_ids:, limit:)
  end

  def most_recently_starred_repo_ids(limit)
    stars_domain.user_most_recently_starred_repo_ids(T.must(self.id), limit)
  end

  # TODO add this method once we adopt the stars domain methods above and
  # unship the `stared_repositories` has_many association
  # def starred_repositories
  #   Repository.where(id: starred_repository_ids)
  # end

  def visible_starred_repositories
    repo_ids = Star.where(user_id: self.id, starrable_type: "Repository").pluck(:starrable_id)
    private_visible_ids = associated_repository_ids(repository_ids: repo_ids)
    public_visible_ids = Repository.where(id: repo_ids - private_visible_ids).where(public: true).pluck(:id)

    Repository.active.where(id: private_visible_ids | public_visible_ids)
  end

  def starred_topics_count
    stars_domain.user_starred_topics_count(T.must(self.id))
  end

  def starred_topic_ids
    stars_domain.user_starred_topic_ids(T.must(self.id))
  end

  def starred_topics(limit: nil)
    starred_topic_ids = stars.
      topics.
      order(created_at: :desc).order(:id).then { |relation| limit ? relation.limit(limit * 2) : relation }.
      pluck(:starrable_id)

    Topic.where(id: starred_topic_ids).
      order(Arel.sql("FIELD(id, #{starred_topic_ids.join(", ")})")).then do |relation|
        limit ? relation.limit(limit) : relation
      end
  end

  # Public: The cached counts of the languages in a user's starred repos.
  #
  # viewer - the currently authenticated User, if any; used to limit which starred repos are counted
  #
  # Returns a Hash[String language name] => Integer repo star count.
  def cached_starred_repository_count_by_language_name(viewer:)
    cache_key = starred_repo_count_by_language_name_cache_key(viewer: viewer)
    GitHub.cache.fetch(cache_key, ttl: 5.minutes) do
      if viewer == self
        starred_repositories_by_language
      else
        starred_public_repositories_by_language
      end
    end
  end

  # All users the user follows that also starred the same repository.
  #
  # repository_id   - The Repository id (required)
  # period          - The period to fetch stars from (required)
  #
  # Returns an ActiveRecord::Relation of Users
  def following_starred(repository_id, period = nil)
    User.following_starred(self.id, repository_id, period).filter_spam_for(self)
  end

  private

  def starred_repo_count_by_language_name_cache_key(viewer:)
    suffix = viewer == self ? "" : ":public"
    "user:repositories:starred_count:#{login}#{suffix}"
  end
end
