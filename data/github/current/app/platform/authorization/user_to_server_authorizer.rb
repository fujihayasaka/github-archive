# typed: true
# frozen_string_literal: true

module Platform
  module Authorization
    class UserToServerAuthorizer < UserViaGranularActorAuthorizer
      def forbidden_message
        "Resource not accessible by integration"
      end

      def github_app_user_to_server_request?
        true
      end

      def granular_actor_on_user_target(target)
        auth_context.current_integration.installations.not_suspended.find_by(target: target)
      end

      alias granular_actor_on_business_target granular_actor_on_user_target
      alias granular_actor_on_organization_target granular_actor_on_user_target

      def granular_actor_on_user_target?(target)
        granular_actor_on_user_target(target).present?
      end

      alias granular_actor_on_business_target? granular_actor_on_user_target?
      alias granular_actor_on_organization_target? granular_actor_on_user_target?

      def granular_actor_on_repository(repository)
        auth_context.current_integration.installations.not_suspended.with_repository(repository).first
      end

      def granular_actor_on_repository?(repository)
        granular_actor_on_repository(repository).present?
      end

      def hydrated_bot_for(installation)
        Platform::Loaders::BotByInstallation.load(installation).sync
      end

      def hydrated_bot_with_null_granular_actor
        return unless auth_context.current_integration

        auth_context.current_integration.async_bot.then do |bot|
          bot.installation = IntegrationInstallation.new(integration: auth_context.current_integration)
        end.sync.bot
      end

      def preloaded_granular_actor_permitted?
        true
      end

      def preloaded_granular_actor
        auth_context.current_integration_installation
      end

      def preloaded_parent_granular_actor_permitted?
        true
      end

      def preloaded_parent_granular_actor
        auth_context.current_parent_integration_installation
      end

      def resource_missing_error_message
        ":resource or :repo is required for integration user requests"
      end
    end
  end
end
