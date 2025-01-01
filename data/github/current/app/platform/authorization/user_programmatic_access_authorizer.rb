# typed: true
# frozen_string_literal: true

module Platform
  module Authorization
    class UserProgrammaticAccessAuthorizer < UserViaGranularActorAuthorizer
      VERB_ALLOW_LIST = %i[edit_issue show_issue pull push].freeze

      def forbidden_message
        "Resource not accessible by personal access token"
      end

      def authorized?(verb, options)
        if restrict_not_onboarded_org_pat?
          auth_context.set_forbidden_message(temporarily_blocked_forbidden_message)
          return false
        end

        # If the flipper is enabled for the user, then delegate the authorization
        # logic to UserViaGranularActorAuthorizer which is the common class for
        # PATs V2 and U2S requests. We override PATs V2 specific methods in this class.
        return super if auth_context.current_user&.patsv2_enabled?

        auth_context.set_forbidden_message(forbidden_message)
        false
      end

      def granular_actor_on_repository(repository)
        auth_context.current_user_programmatic_access.grant_for_repository(repository)
      end

      def granular_actor_on_repository?(repository)
        auth_context.current_user_programmatic_access.grant_for_repository?(repository)
      end

      def granular_actor_on_organization_target(resource)
        auth_context.current_user_programmatic_access.grant_for(resource)
      end

      def granular_actor_on_organization_target?(resource)
        auth_context.current_user_programmatic_access.grant_for?(resource)
      end

      def granular_actor_on_user_target(resource)
        auth_context.current_user_programmatic_access.grant_for(resource)
      end

      def granular_actor_on_user_target?(resource)
        auth_context.current_user_programmatic_access.grant_for?(resource)
      end

      def hydrated_bot_for(programmatic_access_grant)
        case programmatic_access_grant
        when ProgrammaticAccessGrant::ORGANIZATION_TYPE
          Platform::Loaders::BotByOrganizationProgrammaticAccessGrant.load(programmatic_access_grant).sync
        else
          Platform::Loaders::BotByUserProgrammaticAccessGrant.load(programmatic_access_grant).sync
        end
      end

      def hydrated_bot_with_null_granular_actor
        return unless auth_context.current_user_programmatic_access

        auth_context.current_user_programmatic_access.async_bot.then do |bot|
          bot.grant = ProgrammaticAccessGrant.null_grant(auth_context.current_user_programmatic_access)
        end.sync.bot
      end

      def resource_missing_error_message
        ":resource or :repo is required for personal access token requests"
      end

      private

      def restrict_not_onboarded_org_pat?
        auth_context.current_user&.feature_enabled?(:require_onboarding_for_pat_activation) &&
          auth_context&.current_user_programmatic_access&.restrict_not_onboarded_org_pat?
      end

      def temporarily_blocked_forbidden_message
        "Fine-grained PATs have been temporarily reverted to public preview, and your organization did not opt in to use them during the preview. " \
        "All requests using this PAT will be blocked until your organization opts in or fine-grained PATs return to general availability. " \
        "Please check status.github.com and github.blog for updates on this issue."
      end
    end
  end
end
