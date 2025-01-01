# typed: strict
# frozen_string_literal: true

module Stars
  class Creation
    sig { returns(User) }
    attr_reader :user

    sig { returns(Stars::StarrableEntityTypes) }
    attr_reader :entity

    sig { returns(String) }
    attr_reader :context

    sig { returns(T.nilable(Time)) }
    attr_reader :created_at

    sig do
      params(
        user: User,
        entity: Stars::StarrableEntityTypes,
        context: String,
        created_at: T.nilable(Time),
      ).void
    end
    def initialize(user:, entity:, context:, created_at: nil)
      @user = user
      @entity = entity
      @context = context
      @created_at = created_at
    end

    sig { returns(T.any(GH::Result::Ok[StarEntity], GH::Result::Error[String])) }
    def call
      starlike = T.let(nil, T.nilable(T.any(GistStar, Star)))

      Star.transaction do
        entity.transaction do
          attributes = { user:, actor: user, hydro_context_type: context }
          attributes[:created_at] = created_at if created_at

          starlike = if entity.is_a?(Gist)
            GistStar.create!(gist: entity, **attributes)
          else
            Star.create!(starrable: entity, **attributes)
          end
          Stars.domain.reset_caches
        end
      end

      if entity.is_a?(Repositories::IRepository)
        GitHub.instrument "stars.update_count", user:, starred_id: entity.id,
          starred_type: Star::STARRABLE_TYPE_REPOSITORY, context:
      end

      GH::Result::Ok.new(to_entity(T.must(starlike)))
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
