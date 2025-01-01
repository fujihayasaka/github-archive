# typed: true
# frozen_string_literal: true

module Apps
  class Privileged
    class Mobile
      GITHUB_MOBILE_ANDROID_CLIENT_ID = "3f8b8834a91f0caad392".freeze
      GITHUB_MOBILE_IOS_CLIENT_ID = "2cfa9b7a1b57de32dd0d".freeze

      ANDROID_APP_NAME = "GitHub Android"
      ANDROID = {
        alias: :android_mobile,
        database_lookup_attributes: { user_id: :first_party_apps_owner_id, name: ANDROID_APP_NAME },
        inherits: [:first_party],
        capabilities: {
          blockable_first_party_client: true,
          can_auto_approve_oauth_authorization: false, # https://github.com/github/github/issues/117804
          community_org_rewrite: true,
          copilot_agents: true,
          diff_show_patch_entries: true,
          enterprise_avatar_display: true,
          enqueue_mergeable_update: true,
          hide_login_signup_button: false, # Preserves behavior codified in https://github.com/github/github/pull/158680
          mobile_only_schema_mask: true,
          mobile_support_token: true,
          mobile_web_session: true,
          oauth_add_account_picker_override: true,
          oauth_flow_via_unsupported_browser: true,
          organization_oauth_app_policy_exempt: true, # Preserves behavior that used to be inherited from `OauthApplication::CLIENT_APPS_IDS`
          projects_classic_graphql_api_disabled: true,
          proxima_first_party_sync: true,
          releases_only_subscription_status: true,
          subscribe_alive_events: true,
          video_scrubbable: true,
          access_copilot_limited_graphql_api: true, # Allows this app to access GraphQL APIs related to Copilot Free quotas and limits
          access_copilot_consumptive_graphql_api: true, # Allows this app to access GraphQL APIs related to Copilot consumptive users
        },
        properties: {
          proxima_sync_delegate: :DefaultDelegate,
        },
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/mobile"],
      }

      IOS_APP_NAME = "GitHub iOS"
      IOS = {
        alias: :ios_mobile,
        database_lookup_attributes: { user_id: :first_party_apps_owner_id, name: IOS_APP_NAME },
        inherits: [:first_party],
        capabilities: {
          blockable_first_party_client: true,
          can_auto_approve_oauth_authorization: false, # https://github.com/github/github/issues/117804
          community_org_rewrite: true,
          copilot_agents: true,
          diff_show_patch_entries: true,
          enqueue_mergeable_update: true,
          enterprise_avatar_display: true,
          generate_copilot_chat_ssat: true,
          hide_login_signup_button: true, # Preserves behavior codified in https://github.com/github/github/pull/135693
          mobile_only_schema_mask: true,
          mobile_support_token: true,
          mobile_web_session: true,
          oauth_add_account_picker_override: true,
          oauth_flow_via_unsupported_browser: true,
          organization_oauth_app_policy_exempt: true, # Preserves behavior that used to be inherited from `OauthApplication::CLIENT_APPS_IDS`
          projects_classic_graphql_api_disabled: true,
          proxima_first_party_sync: true,
          releases_only_subscription_status: true,
          subscribe_alive_events: true,
          video_scrubbable: true,
          access_copilot_limited_graphql_api: true, # Allows this app to access GraphQL APIs related to Copilot Free quotas and limits
          access_copilot_consumptive_graphql_api: true, # Allows this app to access GraphQL APIs related to Copilot consumptive users
        },
        properties: {
          proxima_sync_delegate: :DefaultDelegate,
        },
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/mobile"],
      }

      def self.app_ids
        @mobile_app_ids ||= Apps::Privileged.oauth_application_ids([:ios_mobile, :android_mobile]).values.compact
      end
    end
  end
end
