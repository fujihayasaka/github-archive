# typed: true
# frozen_string_literal: true

# Maps identity to configuration of GitHub Apps that are owned and operated
# by GitHub and its partners.
module Apps
  class Privileged
    autoload :Actions, "apps/privileged/actions"
    autoload :AllPrivilegedApps, "apps/privileged/all_privileged_apps"
    autoload :ApiHmacClient, "apps/privileged/api_hmac_client"
    autoload :BastianBalthazar, "apps/privileged/bastian_balthazar"
    autoload :CampusExperts, "apps/privileged/campus_experts"
    autoload :ChatopsUnfurl, "apps/privileged/chatops_unfurl"
    autoload :Classroom, "apps/privileged/classroom"
    autoload :CodeScanning, "apps/privileged/code_scanning"
    autoload :Codespaces, "apps/privileged/codespaces"
    autoload :ConfigurationValidator, "apps/privileged/configuration_validator"
    autoload :CopilotCFT, "apps/privileged/copilot_cft"
    autoload :CopilotChat, "apps/privileged/copilot_chat"
    autoload :CopilotPullRequestReviewer, "apps/privileged/copilot_pull_request_reviewer"
    autoload :CopilotIntellijPlugin, "apps/privileged/copilot_intellij_plugin"
    autoload :CopilotJetBrainsLanguageServerAuth, "apps/privileged/copilot_jetbrains_language_server_auth"
    autoload :CopilotXcodeLanguageServerAuth, "apps/privileged/copilot_xcode_language_server_auth"
    autoload :Dependabot, "apps/privileged/dependabot"
    autoload :Desktop, "apps/privileged/desktop"
    autoload :FernandoFerdinand, "apps/privileged/fernando_ferdinand"
    autoload :GCMCore, "apps/privileged/gcm_core"
    autoload :GHN, "apps/privileged/ghn"
    autoload :Gist, "apps/privileged/gist"
    autoload :GitHubCLI, "apps/privileged/github_cli"
    autoload :GitHubConnect, "apps/privileged/github_connect"
    autoload :GitHubEducation, "apps/privileged/github_education"
    autoload :GitHubForMac, "apps/privileged/github_for_mac"
    autoload :GitHubForWindows, "apps/privileged/github_for_windows"
    autoload :GitHubImporter, "apps/privileged/github_importer"
    autoload :GitHubPrism, "apps/privileged/github_prism"
    autoload :GitHubSpamurai, "apps/privileged/github_spamurai"
    autoload :GitHubUnity, "apps/privileged/github_unity"
    autoload :GitSrcMigrator, "apps/privileged/git_src_migrator"
    autoload :Heaven, "apps/privileged/heaven"
    autoload :HelpHub, "apps/privileged/help_hub"
    autoload :MemexAutomation, "apps/privileged/memex_automation"
    autoload :MergeQueue, "apps/privileged/merge_queue"
    autoload :MergeCommitUpdateRefs, "apps/privileged/merge_commit_update_refs"
    autoload :Mobile, "apps/privileged/mobile"
    autoload :Msteams, "apps/privileged/msteams"
    autoload :Neutron, "apps/privileged/neutron"
    autoload :OpenGraph, "apps/privileged/opengraph"
    autoload :Pages, "apps/privileged/pages"
    autoload :PrivateRegistrySecrets, "apps/privileged/private_registry_secrets"
    autoload :ProximaIntegrations, "apps/privileged/proxima_integrations"
    autoload :Query, "apps/privileged/query"
    autoload :Registry, "apps/privileged/registry"
    autoload :Slack, "apps/privileged/slack"
    autoload :TeamSync, "apps/privileged/team_sync"

    TRUTHY = ->(*) { true }
    FALSEY = ->(*) { false }

    # Eventually move this to a database.
    # TODO: Rename aliases :global => :third_party, as "global" has become
    # overloaded and ambiguous.
    def self.default_configuration
      {
        "Integration" => [
          {
            alias: :global, # Applies to all Integrations
            id: ->(*) { nil },
            inherits: [],
            capabilities: {
              abuse_limit_multiplier: false, # https://github.com/github/ecosystem-api/issues/1860
              access_desktop_internal: false, # Allows this app to access Desktop internal endpoints
              access_enterprise_actions_token_api: false, # Allows the App to access the enterprise actions token API
              actions_dynamic_workflows: false, # Allows this app to run dynamic Actions workflows
              auto_uninstall: true, # installations should be uninstalled if the last repository is removed.
              auto_upgrade_permissions: ->(app) { app&.connect_app? },
              can_auto_approve_oauth_authorization: false, # https://github.com/github/github/issues/117804
              can_auto_install_apps_on_oauth_code_exchanged: false,
              can_install_on_security_advisory_repos: false, # https://github.com/github/ecosystem-apps/issues/791
              can_receive_lightweight_access_token_response: false, # https://github.com/github/ecosystem-apps/issues/672
              can_set_loopback_webhook: false, # Used for Actions on GHES
              community_org_rewrite: false,
              create_permissionless_installation_token: false,
              danger_zone_permitted: ->(app) { !app&.connect_app? }, # Third-party Apps can be modified via actions in the Danger Zone, except for GitHub Connect Apps
              access_graphql_discussion_comment_url: false,
              elevated_read_access_on_target: false, # Enables a Global App (E.g. Codespaces) to be granted access to all repositories belonging to a user or organization. ADR: https://github.com/github/ecosystem-apps/pull/1162
              enforce_internal_access_on_token_generation: false, # https://github.com/github/github/pull/141261
              list_current_user_accessible_knowledge_bases: false, # List knowledge bases on behalf of a user (Copilot Chat App)
              administer_knowledge_base: false, # Modify knowledge bases on behalf of a user (Copilot Chat App)
              extend_access_token_expiry: false, # https://github.com/github/ecosystem-apps/issues/792
              follow_repository_transfers: false,
              generate_copilot_cdn_token: false,
              hide_login_signup_button: false,
              always_allow_copilot_access: false, # Does the app get access to Copilot regardless of whether the user's been flagged in?
              installable_on_emus: false,
              installed_globally: false,
              internal_advisory_database: ->(app) { app&.connect_app? }, # Used for enterprise environment Advisory Database syncing (https://github.com/github/ecosystem-apps/discussions/2680)
              ip_allowlist_exempt: false, # Applies to user-to-server only, installations are already exempt.
              ip_allowlist_exempt_for_internal_apis: false,
              static_installation_codespace_permissions: false,
              static_installation_repository_permissions: false,
              manage_packages_permissions: false,
              migrate_pull_reminders: false,
              mobile_web_session: false,
              modifies_check_suite_preferences: true,
              notify_owner_of_private_data_scopes: false, # only applies to OAuth Applications (GitHub Apps don't have scopes)
              oauth_add_account_picker_override: false,
              oauth_flow_via_unsupported_browser: false,
              oauth_authorizations_revocable_by_user: true,
              per_pull_request_permissions: false, # https://github.com/github/ce-engineering/issues/289
              per_repo_rate_limit: false,
              per_repo_user_to_server_tokens_required: false, # Enforce that only scoped user-to-server tokens can be created
              projects_next_graphql_api_disabled: false,
              proxima_first_party_sync: false, # Is this App eligible for sync to Proxima instances
              read_flipper_features: false,
              resolve_actions: false,
              resolve_public_dotcom_actions_via_github_connect: ->(app) { app&.connect_app? },
              resolve_public_dotcom_actions_via_proxima_fallback: false,
              restricted_modification_of_public_resources: false,
              saml_sso_required: true, # Applies to user-to-server only, installations are already exempt.
              skip_oauth_user_eligibility_check: false,
              # Skip Organization::CredentialAuthorizations. The token will not work for SAML-protected resources.
              skip_oauth_organization_credential_authorizations: false,
              # By default, GitHub Apps should notify users about changing user permissions. Please note that if this
              # capability is enabled for an app, it ONLY skips notifications if user permissions change – users will
              # still be notified if other permissions (e.g., organization or repository permissions) are updated.
              # For a full list of notifications that would be skipped by this capability when enabled, see `User::Resources`.
              skip_notification_of_user_permission_changes: false,
              skip_stacks_websocket_updates: false, # by default all third-party Apps are notified for Stacks
              skip_ssh_ca_verification: false, # Allow this integration to skip SSH CA verification
              skip_version_update: false,
              skip_version_update_audit_log: false,
              subscribe_alive_events: false,
              user_installable: true,
              upgrade_default_permissions: false, # Can the app upgrade permissions scopes beyond the default ones?
              integration_installation_multiple_target_permissions: false, # Can the app installation permissions be created on multiple targets?
              bypass_permission_check_for_team_sync_enterprise: false, # See https://github.com/github/external-identities/issues/2338
              codespaces_settings_sync: false, # Used by VS Code settings sync and changes the response of the vsc_internal/validate endpoint
              skip_emu_visibility_cap: false,
              skip_tenant_verification_cap: false, # enforce CAP policy that integration actor's tenant matches tenant which it is accessing on Proxima
              skip_enterprise_access_verification_cap: false, # enforce CAP policy that integration actor's enterprise matches enterprise slug in a "sec-GitHub-allowed-enterprise" header
              skip_emu_ownership_cap: false, # enforce CAP policy that ensures EMUs are not taking actions outside of their enterprise
              verify_account_ownership: false, # Used by Public Keys to know whether the creating app is able to verify account ownership
              is_copilot: false, # denotes Copilot-ish first-party GitHub Apps which generate content that needs to be attributed to AI
              bypass_rest_emu_integration_read_protection: false, # indicates if this app can read apps that are owned by an EMU org/user, without being a member of the EMU business
            },
            properties: {
              allowed_integrations_controller_actions: ->(app) {
                if app&.connect_app?
                  Apps::Privileged::GitHubConnect.allowed_integrations_controller_actions_for_non_site_admins
                else
                  [:all_controller_actions]
                end
              },
              allowed_integrations_controller_actions_for_site_admins: ->(app) {
                if app&.connect_app?
                  Apps::Privileged::GitHubConnect.allowed_integrations_controller_actions_for_site_admins
                else
                  [:all_controller_actions]
                end
              },
              site_scoped_rate_limit: GitHub.api_default_rate_limit,
              hourly_per_repo_rate_limit: 1_000,
              proxima_url_templating_hostname: GitHub::host_name,
            },
            can_auto_install: {},
            custom_instrumentation_events: {},
            owners: ["@github/ecosystem-apps"],
          },
          {
            alias: :first_party, # Applies to all configured first-party (GitHub-owned) Apps, overrides Global configuration
            id: ->(*) { nil },
            inherits: [],
            capabilities: {
              enforce_internal_access_on_token_generation: true, # https://github.com/github/github/pull/146162
              danger_zone_permitted: false, # GitHub-owned Apps should not be modified via actions in The Danger Zone: https://github.com/github/ecosystem-apps/issues/643
              installable_on_emus: true,
              limited_access: ->(app) {
                Apps::Privileged.capable?(:installed_globally, app: app)
              },
              modifies_check_suite_preferences: false,
              # Privileged GitHub Apps don't necessarily need to notify users of permission changes. PLEASE NOTE:
              # this ONLY skips notifications if user permissions change – users will still be notified if other
              # permissions (e.g., organization or repository permissions) are updated. See the comment above where
              # the default value of `skip_notification_of_user_permission_changes` is set for more info.
              skip_notification_of_user_permission_changes: true,
              skip_oauth_user_eligibility_check: true,
              access_package_not_owned_by_target: false, # The default value, false, denies access to private packages not owned by the target User/Org
              skip_tenant_verification_cap: true, # CAP policy enforces integration actor's tenant matches tenant which it is accessing, but this isn't true for internal apps and we allow it
              skip_enterprise_access_verification_cap: false, # disable CAP policy that integration actor's enterprise matches enterprise slug in a "sec-GitHub-allowed-enterprise" header
            },
            properties: {
              allowed_integrations_controller_actions: Apps::Privileged::AllPrivilegedApps.allowed_integrations_controller_actions_for_non_site_admins,
              allowed_integrations_controller_actions_for_site_admins: Apps::Privileged::AllPrivilegedApps.allowed_integrations_controller_actions_for_site_admins,
              packages_authorization_name: "", # Used by Authzd to apply different packages permissions to different Privileged App integrations
              proxima_sync_delegate: :DefaultDelegate,
              proxima_url_templating_hostname: GitHub::host_name,
            },
            can_auto_install: {},
            custom_instrumentation_events: {},
            owners: ["@github/ecosystem-apps"],
          },
          Apps::Privileged::Actions::LAB,
          Apps::Privileged::Actions::PRODUCTION,
          Apps::Privileged::ChatopsUnfurl::PRODUCTION,
          Apps::Privileged::Classroom::PRODUCTION,
          Apps::Privileged::Classroom::STAGING,
          Apps::Privileged::CodeScanning::PRODUCTION,
          *Apps::Privileged::Codespaces::GITHUB_APPS,
          Apps::Privileged::CopilotCFT::PRODUCTION,
          Apps::Privileged::CopilotChat::PRODUCTION,
          Apps::Privileged::CopilotPullRequestReviewer::PRODUCTION,
          Apps::Privileged::CopilotIntellijPlugin::PRODUCTION,
          Apps::Privileged::CopilotJetBrainsLanguageServerAuth::PRODUCTION,
          Apps::Privileged::CopilotXcodeLanguageServerAuth::PRODUCTION,
          Apps::Privileged::Dependabot::PRODUCTION,
          Apps::Privileged::FernandoFerdinand::PRODUCTION,
          Apps::Privileged::GitSrcMigrator::PRODUCTION,
          Apps::Privileged::Heaven::PRODUCTION,
          Apps::Privileged::Heaven::STAGING,
          Apps::Privileged::MemexAutomation::PRODUCTION,
          Apps::Privileged::MergeQueue::PRODUCTION,
          Apps::Privileged::MergeCommitUpdateRefs::PRODUCTION,
          Apps::Privileged::Msteams::PRODUCTION,
          Apps::Privileged::Msteams::STAGING,
          Apps::Privileged::Neutron::PRODUCTION,
          Apps::Privileged::OpenGraph::PRODUCTION,
          Apps::Privileged::Pages::INTEGRATION,
          Apps::Privileged::PrivateRegistrySecrets::PRODUCTION,
          Apps::Privileged::ProximaIntegrations::ACTIONS_RESOLVER_WEU1,
          Apps::Privileged::ProximaIntegrations::ACTIONS_RESOLVER_WUS2_1,
          Apps::Privileged::ProximaIntegrations::ACTIONS_RESOLVER_SDC1,
          Apps::Privileged::ProximaIntegrations::ACTIONS_RESOLVER_AE1,
          Apps::Privileged::ProximaIntegrations::ACTIONS_TEMPLATE_LOADER_WEU1,
          Apps::Privileged::ProximaIntegrations::ACTIONS_TEMPLATE_LOADER_WUS2_1,
          Apps::Privileged::ProximaIntegrations::ACTIONS_TEMPLATE_LOADER_SDC1,
          Apps::Privileged::ProximaIntegrations::ACTIONS_TEMPLATE_LOADER_AE1,
          Apps::Privileged::ProximaIntegrations::ADVISORY_DATABASE_WEU_1,
          Apps::Privileged::ProximaIntegrations::ADVISORY_DATABASE_WUS2_1,
          Apps::Privileged::ProximaIntegrations::ADVISORY_DATABASE_SDC1,
          Apps::Privileged::ProximaIntegrations::ADVISORY_DATABASE_AE1,
          Apps::Privileged::ProximaIntegrations::DEPENDABOT_WEU_1,
          Apps::Privileged::ProximaIntegrations::DEPENDABOT_WUS2_1,
          Apps::Privileged::Slack::PRODUCTION,
          Apps::Privileged::Slack::STAGING,
          Apps::Privileged::TeamSync::PRODUCTION,
        ],
        "OauthApplication" => [
          {
            alias: :global,
            id: ->(*) { nil },
            inherits: [],
            capabilities: {
              access_graphql_discussion_comment_url: false,
              access_internal_graphql_notifications: false, # https://github.com/github/github/pull/159432
              can_auto_approve_oauth_authorization: false, # https://github.com/github/github/issues/117804
              codespaces_settings_sync: false, # Used by VS Code settings sync and changes the response of the vsc_internal/validate endpoint
              community_org_rewrite: false,
              diff_show_patch_entries: false, # Diff.patches: return object entries over object deltas, deltas are just broken in this api entirely since it was never consumed by dotcom and then deprioritized.
              enqueue_mergeable_update: false, # PullRequest.merge_state_status: enqueue promise enqueue_mergeable_update, unknown merge status will never return when it's done or not unless this job gets kicked off.
              enterprise_avatar_display: false, # show GitHub.api_url/enterprise/avatars#{@object.primary_avatar_path} vs object.primary_avatar_url
              generate_copilot_cdn_token: false,
              generate_copilot_chat_ssat: false,
              hide_login_signup_button: false,
              ip_allowlist_exempt: false,
              mobile_only_schema_mask: false, # SchemaMaskRuntimeApp.hidden_by_mobile_app:  will return false, should only be used by mobile
              mobile_support_token: false, # Api::Mobile::Support: defines whether app can POST
              mobile_web_session: false,
              notify_owner_of_private_data_scopes: true,
              oauth_add_account_picker_override: false,
              oauth_flow_via_unsupported_browser: false,
              oauth_authorizations_revocable_by_user: true,
              oauth_checks_access: false,
              projects_next_graphql_api_disabled: false,
              releases_only_subscription_status: false, # Subscribable.viewer_subscription: return releases_only for subscription status response if subscription.thread_type_only?(::Release)
              video_scrubbable: false, # show video tags
              read_flipper_features: false,
              saml_sso_required: true,
              skip_oauth_user_eligibility_check: false,
              skip_tenant_verification_cap: false, # enforce CAP policy that app actor's tenant matches tenant which it is accessing on Proxima
              skip_enterprise_access_verification_cap: false, # enforce CAP policy that integration actor's enterprise matches enterprise slug in a "sec-GitHub-allowed-enterprise" header
            },
            properties: {
              proxima_sync_delegate: :DefaultDelegate,
              proxima_url_templating_hostname: GitHub::host_name
            },
            can_auto_install: {},
            custom_instrumentation_events: {},
            owners: ["@github/ecosystem-apps"],
          },
          {
            alias: :first_party, # Applies to all configured first-party (GitHub-owned) Apps, overrides Global configuration
            id: ->(*) { nil },
            inherits: [],
            capabilities: {
              notify_owner_of_private_data_scopes: false, # Never notify users when internally operated OAuth Apps update scopes
              operated_by_github: true,
              skip_oauth_user_eligibility_check: true,
              skip_tenant_verification_cap: true, # CAP policy enforces app actor's tenant matches tenant which it is accessing, but this isn't true for internal apps and we allow it
              skip_enterprise_access_verification_cap: false, # enforce CAP policy that integration actor's enterprise matches enterprise slug in a "sec-GitHub-allowed-enterprise" header
            },
            properties: {
              proxima_url_templating_hostname: GitHub::host_name,
            },
            can_auto_install: {},
            custom_instrumentation_events: {},
            owners: ["@github/ecosystem-apps"],
          },
          Apps::Privileged::BastianBalthazar::PRODUCTION,
          *Apps::Privileged::CampusExperts::OAUTH_APPS,
          *Apps::Privileged::Codespaces::OAUTH_APPS,
          Apps::Privileged::Desktop::PRODUCTION,
          Apps::Privileged::Desktop::DEVELOPMENT,
          Apps::Privileged::GCMCore::PRODUCTION,
          Apps::Privileged::GHN::PRODUCTION,
          *Apps::Privileged::Gist::OAUTH_APPS,
          Apps::Privileged::GitHubCLI::PRODUCTION,
          *Apps::Privileged::GitHubEducation::OAUTH_APPS,
          Apps::Privileged::GitHubForMac::PRODUCTION,
          Apps::Privileged::GitHubForWindows::PRODUCTION,
          Apps::Privileged::GitHubImporter::PRODUCTION,
          Apps::Privileged::GitHubPrism::PRODUCTION,
          Apps::Privileged::GitHubSpamurai::PRODUCTION,
          Apps::Privileged::GitHubSpamurai::STAGING,
          Apps::Privileged::GitHubSpamurai::REMIX,
          Apps::Privileged::GitHubSpamurai::DEV,
          *Apps::Privileged::GitHubUnity::OAUTH_APPS,
          Apps::Privileged::HelpHub::PRODUCTION,
          Apps::Privileged::HelpHub::STAGING,
          Apps::Privileged::Mobile::ANDROID,
          Apps::Privileged::Mobile::IOS,
          Apps::Privileged::Pages::OAUTH,
        ],
      }
    end

    # Public: The Integration model for the configured 'alias'
    #
    # app_alias  - Symbol: the CONFIGURATION alias assigned to the Integration
    #
    # Returns a Integration or nil.
    def self.integration(app_alias)
      ActiveRecord::Base.connected_to(role: :reading) do
        id_finder = integration_configuration_for(app_alias).fetch(:id, ->() { nil })
        Integration.find_by(id: id_finder.call)
      end
    end

    # Public: The OauthApplication model for the configured 'alias'
    #
    # alias  - Symbol: the CONFIGURATION alias assigned to the OauthApplication
    #
    # Returns a OauthApplication or nil.
    def self.oauth_application(app_alias)
      ActiveRecord::Base.connected_to(role: :reading) do
        id_finder = oauth_configuration_for(app_alias).fetch(:id, ->() { nil })
        OauthApplication.find_by(id: id_finder.call)
      end
    end

    # Public: is the given app configured to be capable of performing the
    # action.
    #
    # action  - Symbol: represents a potentially configured capability.
    # app     - Integration or OauthApplication: the App to check capability
    #           for.
    #
    # Returns a Boolean.
    def self.capable?(action, app:)
      return false if app.nil?
      app_config = Apps::Privileged::Registry.find_configuration(id: app.id, type: app.class.name)
      config_capable?(action, config: app_config, type: app.class.name, app: app)
    rescue ArgumentError # The internal registry raises these when the type of app is invalid
      false
    end

    # Public: a list of all app database IDs that have been granted the
    # given action (capability), for either OAuth or GitHub apps.
    #
    # action  - Symbol: represents a potentially configured capability.
    # type    - String: one of `Apps::Privileged::Registry::VALID_TYPES`
    #           (currently either `OauthAplication` or `Integration`.
    #
    # Returns an Array of Integers.
    def self.all_ids_with_capability(action, type:)
      capable_app_configs = Apps::Privileged::Registry.configuration.fetch(type).find_all do |cfg|
        app_id = cfg[:id].call
        next unless app_id # Ignore inheritable superset configs (those will be evaluated later for real apps)

        config_capable?(action, config: cfg, type: type)
      end

      capable_app_configs.map { |cfg| cfg[:id].call }
    end

    # Internal. Does this config grant the capability to perform the given
    # action? Accounts for direct and inherited capabilities.
    #
    # action  - Symbol: represents a potentially configured capability.
    # config  - Hash: internal app registry configuration.
    # type    - String: One of Apps::Privileged::Registry::VALID_TYPES.
    # app     - (optional) Integration or OauthApplication: passed to callable
    #           capability checks.
    #
    # Returns a Boolean.
    def self.config_capable?(action, config:, type:, app: nil)
      all_capabilities = combined_configuration(config: config, type: type).fetch(:capabilities, {})
      capability = all_capabilities.fetch(action, false)
      capability.respond_to?(:call) ? capability.call(app) : !!capability
    end

    # Internal. Combines an app config with its inherited capabilities and
    # properties to form a complete configuration.
    #
    # config  - Hash. An internal app configuration.
    # type    - String. One of Apps::Privileged::Registry::VALID_TYPES.
    #
    # Returns a Hash representing the complete configuration.
    def self.combined_configuration(config:, type:)
      global_config = Apps::Privileged::Registry.find_configuration(app_alias: :global, type: type)

      combined_config =
        if config.any?
          # The priority of configuration is (highest to lowest):
          # 1. app_config
          # 2. inherited config(s) in descending priority order (E.g. first
          #    is highest priority)
          # 3. global_config
          #
          # NOTE: `capabilities` and `properties` are the only attributes of an
          # app configuration that can be inherited.
          config.tap do |cfg|
            [:capabilities, :properties].each do |inheritable|
              global = global_config.fetch(inheritable, {})
              inherited = inherited_config(config, type:).fetch(inheritable, {})
              app = config.fetch(inheritable, {})

              cfg[inheritable] = global.merge(inherited).merge(app)
            end
          end
        else
          global_config
        end

      combined_config
    end

    # Internal: A consolidated inherited configuration for the given app.
    #
    # Returns an app configuration Hash.
    def self.inherited_config(app_config, type:)
      app_config[:inherits].reverse.reduce({}) do |cfg, cfg_alias|
        cfg.merge(
          Apps::Privileged::Registry.find_configuration(
            app_alias: cfg_alias,
            type: type
          )
        )
      end
    end

    def self.can_auto_install?(trigger_handler, app, opts = {})
      app_config = Apps::Privileged::Registry.find_configuration(id: app.id, type: app.class.name)

      return true if app_config.empty? # Apps that have no explicit checks for this trigger handler can go ahead and install

      app_config.fetch(:can_auto_install, {}).fetch(trigger_handler.to_s, FALSEY).call(opts)
    end

    # Public: Checks if the internal app has access to the specified target based on
    # the limited access configuration.
    #
    # target - The Business, Organization, User to check.
    # app    - Integration or OauthApplication: the App to check access for.
    #
    # Returns a boolean.
    def self.target_accessible_to_limited_app?(target, app:)
      return true unless Apps::Privileged.capable?(:limited_access, app: app)

      accessible_targets = Apps::Privileged.property(:accessible_targets, app: app) || {}
      accessible_targets.transform_keys!(&:downcase)

      target_key = target.display_login.downcase
      accessible_targets.has_key?(target_key)
    end

    # Public: Checks if the internal app has access to the specified repository based on
    # the limited access configuration.
    #
    # repo  - The Repository to check.
    # app   - Integration or OauthApplication: the App to check access for.
    #
    # Returns a boolean.
    def self.repo_accessible_to_limited_app?(repo, app:)
      return true unless Apps::Privileged.capable?(:limited_access, app: app)

      accessible_targets = Apps::Privileged.property(:accessible_targets, app: app) || {}
      accessible_targets.transform_keys!(&:downcase)

      target_key = repo.owner_display_login.downcase
      return false if accessible_targets.empty? || !accessible_targets.has_key?(target_key)

      accessible_repositories = accessible_targets[target_key].map(&:downcase)
      return true if accessible_repositories.empty?

      accessible_repositories.include?(repo.name.downcase)
    end

    # Public: the value configured for the given property name for this App.
    #
    # name    - Symbol: the name of the configured property.
    # app     - Integration or OauthApplication: the App for which to retrieve
    #           a property.
    # id      - Integer: the ID of the App for which to retreive a property.
    # type    - Stryng: the class name of the App for which te retrieve a
    #           property. Must be one of `Integration` or `OauthApplication`.
    #
    # Note: Please supply _either_ `app` OR (`id` AND `type`).
    #
    # Returns the value configured for this property name and App or nil if the
    # App does not have the given property.
    def self.property(name, app: nil, id: nil, type: nil)
      app_id = app.present? ? app.id : id
      app_type = app.present? ? app.class.name : type
      return nil unless app_id.present? && app_type.present?

      app_config = Apps::Privileged::Registry.find_configuration(id: app_id, type: app_type)

      all_properties = combined_configuration(config: app_config, type: app_type).fetch(:properties, {})
      property = all_properties.fetch(name, nil)
      property.respond_to?(:call) ? property.call(app) : property
    end

    # Internal: The configuration Hash for the given alias and type of App.
    #
    # app_alias   - Symbol: the CONFIGURATION alias assigned to the App.
    # type    - Class: One of Integration or OauthApplication.
    #
    # Returns a Hash containing the configuration for the App.
    def self.configuration_for(app_alias, type)
      app_config = Apps::Privileged::Registry.find_configuration(app_alias: app_alias, type: type.name)
    end

    # Internal: The configuration Hash for the named Integration.
    #
    # app_alias  - Symbol: the CONFIGURATION alias assigned to the Integration.
    #
    # Returns a Hash containing the configuration for the Integration.
    def self.integration_configuration_for(app_alias)
      configuration_for(app_alias, Integration)
    end

    # Internal: The configuration Hash for the named OauthApplication.
    #
    # app_alias  - Symbol: the CONFIGURATION alias assigned to the OauthApplication.
    #
    # Returns a Hash containing the configuration for the OauthApplication.
    def self.oauth_configuration_for(app_alias)
      configuration_for(app_alias, OauthApplication)
    end

    # TODO: This method _should not raise_ but should instead return `nil` to
    # maintain parity with the rest of the methods in this class.
    def self.integration_id(app_alias)
      configuration = integration_configuration_for(app_alias)

      ActiveRecord::Base.connected_to(role: :reading) do
        configuration.fetch(:id).call
      end
    rescue KeyError
      raise ArgumentError, "Configuration not found for #{app_alias} integration"
    end

    # Public: a mapping of internal OAuth app aliases to their app's database
    # IDs. Returns preloaded (cached) IDs by default for the sake of
    # performance (meaning each App's configured :id finder proc is only ever
    # evaluated once per process).
    #
    # app_aliases - Array of Symbols. The configured internal aliases of the
    #               apps for which the database IDs should be retrieved
    #
    # Returns a Hash of app alias (Symbol) to ID/nil (Integer, or nil if app
    # not found in registry).
    def self.oauth_application_ids(app_aliases = [])
      return [] if Array(app_aliases).empty?

      app_aliases.inject({}) do |ids_by_alias, app_alias|
        ids_by_alias[app_alias] = Apps::Privileged::Registry.app_id(app_alias: app_alias, type: "OauthApplication")
        ids_by_alias
      end
    end

    def self.custom_instrumentation_event(event, app)
      # currently ignores global and internal configurations, but should only
      # be on a per app basis
      return if app.nil?
      app_config = Apps::Privileged::Registry.find_configuration(id: app.id, type: app.class.name)

      events = app_config.fetch(:custom_instrumentation_events, {})
      return if events.empty?

      events[event]
    end

    def self.integrations_with_access(capability, resource, min_action)
      ActiveRecord::Base.connected_to(role: :reading) do
        integration_ids = all_ids_with_capability(capability, type: "Integration")
        return [] if integration_ids.empty?

        integrations = Integration.includes(:latest_version).where(id: integration_ids)
        default_permissions = DefaultIntegrationPermission.where(integration_version_id: integrations.map { |integration| integration.latest_version.id }, resource:)
          .index_by(&:integration_version_id)

        integrations.filter_map do |integration|
          permissions = default_permissions[integration.latest_version.id]
          next false if permissions.nil?

          min_action_satisfied =
            T.must(Permission.actions[permissions.action]) >= T.must(Permission.actions[min_action])

          integration if min_action_satisfied
        end
      end
    end
  end
end
