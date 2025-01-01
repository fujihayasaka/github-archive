# typed: true
# frozen_string_literal: true

module Platform
  module Authorization
    class GlobalUserToServerAuthorizer < UserViaGranularActorAuthorizer

      Target        = T.type_alias { T.any(Business, Organization, User) }
      GranularActor = T.type_alias { T.any(GlobalIntegrationInstallation, SiteScopedIntegrationInstallation) }

      def initialize(context, result)
        @granular_actor_cache = T.let({}, T::Hash[T.any(Target, Repository), T.nilable(GranularActor)])
        @user_to_server_authorizer = UserToServerAuthorizer.new_from_context(context, result)

        super
      end

      def forbidden_message
        @user_to_server_authorizer.forbidden_message
      end

      def github_app_user_to_server_request?
        true
      end

      sig { params(target: Target).returns(T.nilable(GranularActor)) }
      def granular_actor_on_target(target)
        return @granular_actor_cache[target] if @granular_actor_cache.key?(target)

        @granular_actor_cache[target] = begin
          if preloaded_granular_actor.present?
            preloaded_granular_actor&.target == target ? preloaded_granular_actor : nil
          else
            GlobalIntegrationInstallation.new(auth_context.current_integration, target)
          end
        end
      end

      sig { params(target: Business).returns(T.nilable(GranularActor)) }
      def granular_actor_on_business_target(target)
        granular_actor_on_target(target)
      end

      sig { params(target: Organization).returns(T.nilable(GranularActor)) }
      def granular_actor_on_organization_target(target)
        granular_actor_on_target(target)
      end

      sig { params(target: User).returns(T.nilable(GranularActor)) }
      def granular_actor_on_user_target(target)
        granular_actor_on_target(target)
      end

      sig { params(target: Business).returns(T::Boolean) }
      def granular_actor_on_business_target?(target)
        granular_actor_on_business_target(target).present?
      end

      sig { params(target: Organization).returns(T::Boolean) }
      def granular_actor_on_organization_target?(target)
        granular_actor_on_organization_target(target).present?
      end

      sig { params(target: User).returns(T::Boolean) }
      def granular_actor_on_user_target?(target)
        granular_actor_on_user_target(target).present?
      end

      sig { params(repository: Repository).returns(T.nilable(GranularActor)) }
      def granular_actor_on_repository(repository)
        return @granular_actor_cache[repository] if @granular_actor_cache.key?(repository)

        @granular_actor_cache[repository] = begin
          if preloaded_granular_actor.present?
            # In Codespaces, there may be times a
            # SiteScopedIntegrationInstallation is installed on 'all'
            # repositories for the target and have also have access to a single
            # repo outside of the target.
            #
            # For example, the user's dotfiles repository.
            if preloaded_granular_actor&.repository_ids(repository_ids: [repository.id]).any? || \
                preloaded_granular_actor&.installed_on_individual_repository_ids(repository_ids: [repository.id]).any?
              preloaded_granular_actor
            end
          else
            granular_actor = GlobalIntegrationInstallation.new(auth_context.current_integration, T.must(repository.owner))
            Repository::Resources.filter(granular_actor.permissions).any? ? granular_actor : nil
          end
        end
      end

      sig { params(repository: Repository).returns(T::Boolean) }
      def granular_actor_on_repository?(repository)
        granular_actor_on_repository(repository).present?
      end

      def hydrated_bot_for(installation)
        @user_to_server_authorizer.hydrated_bot_for(installation)
      end

      def hydrated_bot_with_null_granular_actor
        @user_to_server_authorizer.hydrated_bot_with_null_granular_actor
      end

      def preloaded_granular_actor_permitted?
        true
      end

      def preloaded_granular_actor
        @user_to_server_authorizer.preloaded_granular_actor
      end

      def resource_missing_error_message
        @user_to_server_authorizer.resource_missing_error_message
      end
    end
  end
end
