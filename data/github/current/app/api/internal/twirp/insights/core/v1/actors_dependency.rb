# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Insights
  module Core
    module V1
      module ActorsDependency
        def build_actor(actor)
          if actor.is_a?(User) && actor.user?
            { id: actor.id, id_string: actor.login, type: :TYPE_USER, analytics_tracking_id: actor.analytics_tracking_id }
          elsif actor.is_a?(Organization) && actor.organization?
            { id: actor.id, id_string: actor.login, type: :TYPE_ORGANIZATION, analytics_tracking_id: actor.analytics_tracking_id }
          elsif actor.is_a?(Repository)
            { id: actor.id, id_string: actor.name_with_owner, type: :TYPE_REPOSITORY }
          elsif actor.is_a?(Business)
            { id: actor.id, id_string: actor.slug, type: :TYPE_BUSINESS }
          else
            { id: actor.id, type: :TYPE_INVALID }
          end
        end
      end
    end
  end
end
