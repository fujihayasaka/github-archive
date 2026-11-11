# typed: true
# frozen_string_literal: true

module Platform
  module Helpers
    module ActorLimiter
      class << self
        def check(clazz, context)
          return true if Platform.safe_origin?(context[:origin])
          actors = clazz.limit_actors_to
          return true if actors.empty?
          graphql_name = clazz.graphql_name

          valid = {
            github_app: false,
            oauth_app: false,
            user: false,
          }

          valid[:github_app] = check_github_app(actors, graphql_name, context)
          valid[:oauth_app] = check_oauth_app(actors, graphql_name, context)
          valid[:user] = check_user(actors, graphql_name, context)

          unless actors.any? { |actor| valid[actor] }
            raise_error(graphql_name, actors)
          end

          true
        end

        private

        def check_github_app(actors, graphql_name, context)
          if actors.include?(:github_app)
            return false unless context[:integration].present?
          end

          true
        end

        def check_oauth_app(actors, graphql_name, context)
          if actors.include?(:oauth_app)
            return false unless context[:oauth_app].present?
          end

          true
        end

        def check_user(actors, graphql_name, context)
          if actors.include?(:user)
            return false unless context[:viewer].present?

            # This is not a "pure" user and represents individuals authenticating through an app.
            # In both an OAuth app and a user-server scenario, `viewer` is set to the actual user
            # that authenticated. In a server-server scenario, `viewer` is set to the App bot.
            # Since both of these are not "regular" users, they shouldn't pass a scenario where an
            # actor is expected to just be a human user with a PAT.
            if context[:oauth_app].present? || context[:integration].present?
              return false
            end
          end

          true
        end

        def raise_error(graphql_name, actors)
          actor_names = actors.map do |actor|
            case actor
            when :github_app
              "a GitHub App"
            when :oauth_app
              "an OAuth App"
            when :user
              "a user"
            end
          end
          raise Platform::Errors::Forbidden.new("`#{graphql_name}` can only be accessed by #{actor_names.to_sentence(two_words_connector: " or ")}")
        end
      end
    end
  end
end
