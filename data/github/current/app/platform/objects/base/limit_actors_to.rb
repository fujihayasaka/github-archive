# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Base < GraphQL::Schema::Object
      module LimitActorsTo
        include Kernel

        ACTOR_TYPES = [:user, :oauth_app, :github_app].freeze

        def limit_actors_to(actors = [])
          return (@limited_actors || []) if actors.blank?
          validate(actors)
          @limited_actors = actors
        end

        private def validate(actors)
          unless (bad_actors = actors - ACTOR_TYPES).empty?
            raise Platform::Errors::Internal.new("Unexpected actors defined in the schema: #{bad_actors}")
          end
          true
        end
      end
    end
  end
end
