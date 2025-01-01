# typed: strict
# frozen_string_literal: true

module Stars
  class Creation
    extend T::Sig

    sig { returns(User) }
    attr_reader :user

    sig { returns(GH::Auth::Actor) }
    attr_reader :actor

    sig { returns(Stars::StarrableEntityTypes) }
    attr_reader :entity

    sig { returns(String) }
    attr_reader :context

    sig do
      params(
        user: User,
        actor: GH::Auth::Actor,
        entity: Stars::StarrableEntityTypes,
        context: String
      ).void
    end
    def initialize(user:, actor:, entity:, context:)
      @user = user
      @actor = actor
      @entity = entity
      @context = context
    end

    sig { returns(GH::Result[StarEntity]) }
    def execute
      star_obj = T.let(nil, T.nilable(T.any(GistStar, Star)))

      Star.transaction do
        entity.transaction do
          star_obj = entity.stars.create!(user:, actor:, hydro_context_type: context)
          entity.clear_preloaded_batch_method_value(:starred_by?, user)
        end
      end

      if entity.is_a?(Repositories::IRepository)
        GitHub.instrument "stars.update_count", user:, starred_id: entity.id,
          starred_type: Star::STARRABLE_TYPE_REPOSITORY
      end

      GH::Result::Ok.new(to_entity(T.must(star_obj)))
    rescue ActiveRecord::RecordNotUnique
      GH::Result::Error::NotUnique.new("user already starred this entity")
    end

    private

    sig { params(star: T.any(Star, GistStar)).returns(StarEntity) }
    def to_entity(star)
      return StarEntity.new(**star.attributes) if star.is_a?(Star)

      StarEntity.new(
        id: star.id,
        user_id: star.user_id,
        starrable_id: star.gist_id,
        starrable_type: Star::STARRABLE_TYPE_GIST,
        user_hidden: false,
        created_at: star.created_at
      )
    end
  end
end
