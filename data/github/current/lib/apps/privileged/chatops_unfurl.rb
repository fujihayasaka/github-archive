# typed: true
# frozen_string_literal: true

module Apps
  class Privileged
    class ChatopsUnfurl
      APP_NAME = "chatops-unfurl"

      def self.id_finder(app_name)
        ->() {
          return nil if GitHub.enterprise?

          Integration.find_by(
            owner_id: GitHub.trusted_apps_owner_id,
            name: app_name,
          )&.id
        }
      end

      # This App is used by our Slack/Teams integrations to unfurl links for
      # logged out users.
      #
      # !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      # THIS APP SHOULD NEVER BE GRANTED ANY PERMISSIONS! It should only be able
      # to access public resources.
      # !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      #
      # For more info, see https://github.com/github/slack/issues/1957.
      PRODUCTION = {
        alias: :chatops_unfurl,
        id: id_finder(APP_NAME),
        inherits: [:first_party],
        capabilities: {
          enforce_internal_access_on_token_generation: !Rails.env.development?,
          limited_access: false,
          installed_globally: true,
          user_installable: false,
          access_graphql_discussion_comment_url: true,
          ip_allowlist_exempt: true,
          proxima_first_party_sync: true,
        },
        properties: {
          site_scoped_rate_limit: GitHub.api_tier_two_rate_limit,
          proxima_sync_delegate: :DefaultDelegate,
        },
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/notifications"],
      }


      def self.seed_database!(app_url:, insecure_ssl:, client_key:, client_secret:, public_key:)
        return if id_finder(APP_NAME).call.present?

        integration_attributes = {
          owner: GitHub.trusted_oauth_apps_owner,
          name: APP_NAME,
          url: app_url,
          key: client_key,
          visibility: :private_visibility,
          skip_restrict_names_with_github_validation: true,
          skip_generate_slug: true,
          no_repo_permissions_allowed: true,
          user_token_expiration_enabled: false,
        }

        app = Integration.create!(integration_attributes)

        if public_key.length > 0
          app.public_keys.create!(creator: GitHub.trusted_oauth_apps_owner, skip_generate_key: true, public_pem: public_key)
        end

        app.client_secrets.create!(creator: User.ghost,
          secret_hash: OauthApplicationClientSecret.hash_for(client_secret),
          secret_last_eight: client_secret.last(8))

        app
      end

      def self.delete_app!
        if (app = Apps::Privileged.integration(:chatops_unfurl))
          app.destroy!
        end
      end
    end
  end
end
