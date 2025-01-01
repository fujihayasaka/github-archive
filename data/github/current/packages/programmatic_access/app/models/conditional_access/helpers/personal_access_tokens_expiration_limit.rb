# typed: true
# frozen_string_literal: true

module ConditionalAccess
  module Helpers
    module PersonalAccessTokensExpirationLimit
      extend T::Sig

      private

      EXPIRATION_ERROR_MESSAGE = <<~MSG.squish
        The '%{limit_enforcer_name}' %{limit_enforcer_type} forbids access via a %{token_type} if the token's lifetime is greater than %{expiration_limit} days.
        Please adjust your token's lifetime at the following URL: %{settings_url}
        MSG

      # Private: Build an error message for the personal access tokens expiration limit policy.
      #
      # Returns a string.
      sig { params(target: T.any(Business, Organization), actor: User).returns(String) }
      def expiration_limit_exceeded_error_message(target, actor)
        access = actor.programmatic_access || actor.oauth_access
        # Business or Organization enforcing the expiration limit
        limit_enforcer = limit_enforcer(target, access)
        limit_enforcer_name = limit_enforcer.is_a?(Organization) ? limit_enforcer.display_login : limit_enforcer.name
        limit_enforcer_type = limit_enforcer.is_a?(Organization) ? "organization" : "enterprise"
        EXPIRATION_ERROR_MESSAGE % {
          limit_enforcer_name: limit_enforcer_name,
          limit_enforcer_type: limit_enforcer_type,
          token_type: access.pat_type_name,
          expiration_limit: ProgrammaticAccessTokenLifetimeConfiguration.expiration_limit_for(limit_enforcer, access.pat_type),
          settings_url: settings_url(access)
        }
      end

      # Private: Determine whether the organization or its business enforces the policy.
      # If both the organization and its business enforce the policy, the most restrictive policy takes precedence.
      #
      # Returns an instance of Business or Organization.
      sig { params(target: T.any(Business, Organization), access: T.any(OauthAccess, UserProgrammaticAccess)).returns(T.any(Business, Organization)) }
      def limit_enforcer(target, access)
        case target
        when Business
          target
        when Organization
          return target if target.business.blank?

          org_limit = ProgrammaticAccessTokenLifetimeConfiguration.expiration_limit_for(target, access.pat_type)
          biz_limit = ProgrammaticAccessTokenLifetimeConfiguration.expiration_limit_for(T.must(target.business), access.pat_type)

          # Return the entity with the lowest limit
          return target if biz_limit.nil? || org_limit && org_limit > biz_limit
          T.must(target.business)
        end
      end

      # Private: Url to the settings page for a fine-grained or classic PAT.
      #
      # Returns a string.
      sig { params(access: T.any(OauthAccess, UserProgrammaticAccess)).returns(String) }
      def settings_url(access)
        base_url = "https://#{GitHub.host_name_with_tenant}"
        base_url + settings_path(access)
      end

      # Private: Path to the settings page for a fine-grained or classic PAT.
      #
      # Returns a string.
      sig { params(access: T.any(OauthAccess, UserProgrammaticAccess)).returns(String) }
      def settings_path(access)
        case access
        when OauthAccess
          Rails.application.routes.url_helpers.settings_user_token_path(access)
        when UserProgrammaticAccess
          Rails.application.routes.url_helpers.settings_user_access_token_path(access)
        end
      end
    end
  end
end
