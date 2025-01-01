# typed: true
# frozen_string_literal: true

require "apps/installation_instrumenter/codespaces"

module Apps
  class Privileged
    class Codespaces
      PREBUILD_DYNAMIC_WORKFLOW_INTEGRATION_NAME = "codespaces"

      # The VS Code OAuth secret data. Because VS Code is a client side app the OAuth "secret" isn't really secret.
      VSCODE_OAUTH_APP_SECRET = {
        secret_hash: "MfLkwDXfqFsERkbMqu1TPqxfTQ5OUvr1D3/5be5ER+Y=",
        secret_last_eight: "693f14cd",
      }

      def self.integration_id_finder(key)
        ->() {
          Integration.find_by(key: key)&.id
        }
      end

      def self.oauth_app_id_finder(key)
        ->() {
          OauthApplication.find_by(key: key)&.id
        }
      end

      PRODUCTION = {
        alias: :codespaces_production,
        id: integration_id_finder(GitHub.codespaces_app_key),
        inherits: [:first_party],
        capabilities: {
          access_codespaces: true,
          auto_uninstall: false,
          can_auto_approve_oauth_authorization: true,
          enforce_internal_access_on_token_generation: false,
          installed_globally: true,
          limited_access: false,
          manage_packages_permissions: true,
          # Triggers old behavior of writing fine-grained package permissions to the database
          # Must be combined with `manage_packages_permissions` to be effective
          # See https://github.com/github/github/pull/286073
          write_legacy_site_scoped_fine_grained_package_permissions: true,
          skip_ssh_ca_verification: true,
          skip_version_update: true,
          static_installation_codespace_permissions: true,
          static_installation_repository_permissions: true,
          per_repo_rate_limit: true, # https://github.com/github/codespaces/issues/12295
          repo_owner_rate_limit: true,
          per_repo_user_to_server_tokens_required: true, # Enforce that only scoped user-to-server tokens can be created
          user_installable: false,
          generate_copilot_cdn_token: true,
          always_allow_copilot_access: false,
          elevated_read_access_on_target: true,
          integration_installation_multiple_target_permissions: true,
          read_flipper_features: true,
          upgrade_default_permissions: true, # Can the app upgrade permissions scopes beyond the default ones?
          codespaces_settings_sync: true,
          skip_oauth_organization_credential_authorizations: true, # We will write the org credential authorization ourselves, see https://github.com/github/codespaces/issues/14728
          access_package_not_owned_by_target: true, # Allows access to private packages not owned by the target User/Org (i.e. Codespaces created by a User)
          proxima_first_party_sync: true,
        },
        properties: {
          static_installation_codespace_permissions: {
            "codespace_metadata" => :read
          },
          static_installation_repository_permissions: {
            "metadata" => :read
          },
          audit_log_secrets_app_name: "codespaces",
          secrets_event_subject: "integration",
          site_scoped_rate_limit: 50_000, # per hour
          hourly_per_repo_rate_limit: 1_000,
          oauth_access_expiry: ::Codespaces::MAX_SESSION_TIME,
          refresh_token_expiry: ::Codespaces::MAX_SESSION_TIME,
          packages_authorization_name: "codespaces",
          proxima_sync_delegate: :DefaultDelegate,
        },
        can_auto_install: {},
        custom_instrumentation_events: {
          create_installation: ->(installation, configurations) {
            Apps::InstallationInstrumenter::Codespaces.create_event_details(installation, configurations)
          },
          delete_installation: ->(installation, *) {
            Apps::InstallationInstrumenter::Codespaces.delete_event_details(installation)
          },
          repositories_added: ->(installation, configurations) {
            Apps::InstallationInstrumenter::Codespaces.repositories_added_event_details(installation, configurations)
          },
          repositories_removed: ->(installation, configurations) {
            Apps::InstallationInstrumenter::Codespaces.repositories_removed_event_details(installation, configurations)
          }
        },
        owners: ["@github/codespaces"],
      }

      VSCODE_AUTH_PROVIDER_KEY = "Iv1.ae51e546bef24ff1"

      VSCODE_AUTH_PROVIDER = {
        alias: :vscode_auth_provider,
        id: integration_id_finder(VSCODE_AUTH_PROVIDER_KEY),
        inherits: [:first_party], # TODO: Review this app's capabilities. Should it be considered first-party?
        capabilities: {
          access_codespaces: true,
          enforce_internal_access_on_token_generation: false,
          generate_copilot_cdn_token: true,
        },
        properties: {},
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/codespaces"],
      }

      VM_SECRETS = {
        alias: :codespaces_vm_secrets,
        id: integration_id_finder(GitHub.codespaces_vm_secrets_app_key),
        inherits: [],
        capabilities: {
          proxima_first_party_sync: true,
        },
        properties: {
          proxima_sync_delegate: :DefaultDelegate,
        },
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/codespaces"],
      }

      # These are all OAuth apps:

      VSCODE_OSS = {
        alias: :vscode_oss,
        id: oauth_app_id_finder("a5d3c261b032765a78de"),
        inherits: [:first_party], # TODO: Review this app's capabilities. Should it be considered first-party?
        capabilities: {
          access_codespaces: true,
          enforce_internal_access_on_token_generation: false,
        },
        properties: {},
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/codespaces"],
      }

      VSCODE_EXPLORATION = {
        alias: :vscode_exploration,
        id: oauth_app_id_finder("94e8376d3a90429aeaea"),
        inherits: [:first_party], # TODO: Review this app's capabilities. Should it be considered first-party?
        capabilities: {
          access_codespaces: true,
          enforce_internal_access_on_token_generation: false,
        },
        properties: {},
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/codespaces"],
      }

      VSCODE_VSO = {
        alias: :vscode_vso,
        id: oauth_app_id_finder("3d4be8f37a0325b5817d"),
        inherits: [:first_party], # TODO: Review this app's capabilities. Should it be considered first-party?
        capabilities: {
          access_codespaces: true,
          enforce_internal_access_on_token_generation: false,
        },
        properties: {},
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/codespaces"],
      }

      VSCODE_VSO_PPE = {
        alias: :vscode_vso_ppe,
        id: oauth_app_id_finder("eabf35024dc2e891a492"),
        inherits: [:first_party], # TODO: Review this app's capabilities. Should it be considered first-party?
        capabilities: {
          access_codespaces: true,
          enforce_internal_access_on_token_generation: false,
        },
        properties: {},
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/codespaces"],
      }

      VSCODE_KEY = "baa8a44b5e861d918709"
      VSCODE = {
        alias: :vscode,
        id: oauth_app_id_finder(VSCODE_KEY),
        inherits: [:first_party], # TODO: Review this app's capabilities. Should it be considered first-party?
        capabilities: {
          access_codespaces: true,
          enforce_internal_access_on_token_generation: false,
        },
        properties: {},
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/codespaces"],
      }

      VSCODE_INSIDERS = {
        alias: :vscode_insiders,
        id: oauth_app_id_finder("31f02627809389d9f111"),
        inherits: [:first_party], # TODO: Review this app's capabilities. Should it be considered first-party?
        capabilities: {
          access_codespaces: true,
          enforce_internal_access_on_token_generation: false,
        },
        properties: {},
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/codespaces"],
      }

      VSCODE_DEV = {
        alias: :vscode_dev,
        id: oauth_app_id_finder("84383ebd8a7c5f5efc5c"),
        inherits: [:first_party], # TODO: Review this app's capabilities. Should it be considered first-party?
        capabilities: {
          access_codespaces: true,
          enforce_internal_access_on_token_generation: false,
        },
        properties: {},
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/codespaces"],
      }

      VSCODE_AUTH_SERVER_KEY = "01ab8ac9400c4e429b23".freeze
      VSCODE_AUTH_SERVER = {
        alias: :vscode_auth_server,
        id: oauth_app_id_finder(VSCODE_AUTH_SERVER_KEY),
        inherits: [:first_party], # TODO: Review this app's capabilities. Should it be considered first-party?
        capabilities: {
          access_codespaces: true,
          blockable_first_party_client: true,
          create_tokens_for_ssh_key_verification: true, # Preserves behavior that used to be hard-coded in `OauthApplication#github_desktop?`
          enforce_internal_access_on_token_generation: false,
          generate_copilot_cdn_token: true,
          organization_oauth_app_policy_exempt: true, # Preserves behavior that used to be inherited from `OauthApplication::CLIENT_APPS_IDS`
          proxima_first_party_sync: true,
          verify_account_ownership: true # Preserves behavior that used to be hard-coded in `OauthApplication#github_desktop?`
        },
        properties: {
          proxima_sync_delegate: :DefaultDelegate,
        },
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/codespaces"],
      }

      VSCODE_AUTH_SERVER_STAGING = {
        alias: :vscode_auth_server_staging,
        id: oauth_app_id_finder("c8d3980f24ffff70fbd6"),
        inherits: [:first_party], # TODO: Review this app's capabilities. Should it be considered first-party?
        capabilities: {
          access_codespaces: true,
          blockable_first_party_client: true,
          enforce_internal_access_on_token_generation: false,
          generate_copilot_cdn_token: true,
          organization_oauth_app_policy_exempt: true,
        },
        properties: {},
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/codespaces"],
      }

      LWE_KEY = "f454531869ce20e0bcd8"
      LWE = {
        alias: :lightweight_web_editor,
        id: oauth_app_id_finder(LWE_KEY),
        inherits: [:first_party], # TODO: Review this app's capabilities. Should it be considered first-party?
        capabilities: {
          access_codespaces: true,
          enforce_internal_access_on_token_generation: false,
          organization_oauth_app_policy_exempt: true,
          codespaces_settings_sync: true,
        },
        properties: {},
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/codespaces"],
      }

      VISUAL_STUDIO_KEY = "a200baed193bb2088a6e"
      VISUAL_STUDIO = {
        alias: :visual_studio,
        id: oauth_app_id_finder(VISUAL_STUDIO_KEY),
        inherits: [:first_party], # TODO: Review this app's capabilities. Should it be considered first-party?
        capabilities: {
          access_codespaces: true,
          blockable_first_party_client: true,
          create_tokens_for_ssh_key_verification: true, # Preserves behavior that used to be hard-coded in `OauthApplication#github_desktop?`
          enforce_internal_access_on_token_generation: false,
          generate_copilot_cdn_token: true,
          organization_oauth_app_policy_exempt: true, # Preserves behavior that used to be inherited from `OauthApplication::CLIENT_APPS_IDS`
          proxima_first_party_sync: true,
          codespaces_settings_sync: false,
          verify_account_ownership: true # Preserves behavior that used to be hard-coded in `OauthApplication#github_desktop?`
        },
        properties: {
          proxima_sync_delegate: :DefaultDelegate,
        },
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/codespaces"],
      }

      # this is the jetbrains codespaces app (built by GitHub)
      JETBRAINS_KEY = "640fc1ee1c241c83eccb"
      JETBRAINS = {
        alias: :jetbrains,
        id: oauth_app_id_finder(JETBRAINS_KEY),
        inherits: [:first_party], # TODO: Review this app's capabilities. Should it be considered first-party?
        capabilities: {
          enforce_internal_access_on_token_generation: false,
          organization_oauth_app_policy_exempt: true,
          proxima_first_party_sync: true,
        },
        properties: {
          proxima_sync_delegate: :DefaultDelegate,
        },
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/codespaces"],
      }

      # this is the jetbrains ide oauth app (built by JetBrains)
      # we grant a single permission to this even though it's a 3p app
      # https://github.com/github/ecosystem-apps/issues/5479
      JETBRAINS_IDE_KEY = "58566862bd2a5ff748fb"
      JETBRAINS_IDE = {
        alias: :jetbrains_ide,
        id: oauth_app_id_finder(JETBRAINS_IDE_KEY),
        inherits: [],
        capabilities: {
          generate_copilot_cdn_token: true, # granted https://github.com/github/ecosystem-apps/issues/5315#issuecomment-2079768439
        },
        properties: {},
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/copilot-editor-team"],
      }

      GITHUB_APPS = [
        PRODUCTION,
        VSCODE_AUTH_PROVIDER,
        VM_SECRETS,
      ]

      OAUTH_APPS = [
        VSCODE_OSS,
        VSCODE_EXPLORATION,
        VSCODE_VSO,
        VSCODE_VSO_PPE,
        VSCODE,
        VSCODE_INSIDERS,
        VSCODE_DEV,
        VSCODE_AUTH_SERVER,
        VSCODE_AUTH_SERVER_STAGING,
        LWE,
        VISUAL_STUDIO,
        JETBRAINS,
        JETBRAINS_IDE
      ]

      INTEGRATION_PERMISSONS = {
        "actions" => :read,
        "checks" => :read,
        "codespaces" => :read,
        "codespaces_secrets" => :write,
        "codespaces_user_secrets" => :write,
        "codespace_metadata" => :read,
        "contents" => :write,
        "deployments" => :read,
        "discussions" => :read,
        "issues" => :write,
        "metadata" => :read,
        "organization_packages" => :read,
        "packages" => :read,
        "pages" => :read,
        "pull_requests" => :write,
        "pull_requests_comment_only_reviews" => :write,
        "pull_requests_from_forks" => :write,
        "repository_projects" => :read,
        "statuses" => :read,
        "workflows" => :write
      }.freeze

      DEV_PLANS = {
        production: {
          "EastUs" =>  {
            name: "plan-4132d58e-85ba-45a1-b8b4-46945bba48ec",
            resource_group: "EastUs-0d8cde39-035f-4cb9-8cc7-e651fff488b7"
          },
          "SouthEastAsia" => {
            name: "plan-032a341c-47ec-4d83-a9e6-d78afac880dd",
            resource_group: "SouthEastAsia-dc862f09-08bf-47b3-9a9f-af8edc062f92"
          },
          "WestEurope" => {
            name: "plan-2e0904e8-7d58-465c-b2ed-2a60601276e5",
            resource_group: "WestEurope-c58d2c44-0305-4022-9e0f-968e8eb8826b"
          },
          "WestUs2" => {
            name: "plan-93f8115e-b03d-427b-a807-12f388db46a9",
            resource_group: "WestUs2-b047731f-8d43-403b-9523-c0b8393be4d2"
          },
        },
        ppe: {
          "SouthEastAsia" => {
            name: "plan-fcdd9081-e7dd-4b25-99cf-ed6be3c11f3a",
            resource_group: "SouthEastAsia-dc862f09-08bf-47b3-9a9f-af8edc062f92"
          },
          "EastUs" => {
            name: "plan-6e21a80d-be54-406d-967a-30aa57343752",
            resource_group: ""
          },
          "CanadaCentral" => {
            name: "plan-8588e08c-4c0f-410a-a0e4-1d3f84e2362b",
            resource_group: ""
          },
        },
        development: {
          "WestEurope" =>  {
            name: "plan-d527a06b-eec7-419b-9eb7-b50b48924bb1",
            resource_group: "WestEurope-c58d2c44-0305-4022-9e0f-968e8eb8826b"
          },
          "WestUs2" =>  {
            name: "plan-4dd3dc9f-d2b9-4726-b758-d8e7d8976ca6",
            resource_group: "WestUs2-b047731f-8d43-403b-9523-c0b8393be4d2"
          },
        },
        local: {
          "WestEurope" => {
            name: "plan-bd4cc8ac-f1ba-421e-a9cb-db82b0c87e08",
            resource_group: "WestEurope-c58d2c44-0305-4022-9e0f-968e8eb8826b"
          },
          "WestUs2" => {
            name: "plan-5f7b350c-f510-4aec-b8b5-1c6996991003",
            resource_group: "WestUs2-b047731f-8d43-403b-9523-c0b8393be4d2"
          },
        },
        canary: {
          "EastUs2Euap" => {
            name: "plan-fd81b1ae-a871-11eb-8c25-8fdbd6d11113",
            resource_group: "EastUs2Euap-ed20329e-b448-11eb-99f8-b7acb6aad24e"
          },
        }
      }.freeze

      def self.seed!(tenant_slug: nil)
        seed_apps!
        seed_plans!(tenant_slug: tenant_slug)

        puts "Done!"
      end

      def self.seed_apps!
        # Production apps are manually created for GitHub.com and then synced to Proxima stamps via:
        # https://thehub.github.com/epd/engineering/products-and-services/dotcom/apps/proxima/how-to-synchronize-apps-on-proxima/
        # So the only time we'd want to actually create them is in development.
        return if Rails.env.production? # rubocop:disable GitHub/DoNotBranchOnRailsEnv

        update_codespaces_app!
        update_vscode_oauth_app!
        update_jetbrains_app!
        update_vm_secrets_app!
      end

      def self.update_vm_secrets_app!
        properties = {
          key: GitHub.codespaces_vm_secrets_app_key,
          owner: GitHub.trusted_oauth_apps_owner,
          name: "GitHub Codespaces VM Secrets",
          url: "https://github.com",
          skip_generate_slug: true,
        }
        app = Integration.find_by(key: GitHub.codespaces_vm_secrets_app_key)

        if app.nil?
          puts "Creating Codespaces VM Secrets app..."
          app = Integration.create!(**properties)
        else
          puts "Updating existing Codespaces VM Secrets app..."
          app.update!(**properties)
        end
      end

      def self.update_codespaces_app!
        properties = {
          key: GitHub.codespaces_app_key,
          owner: GitHub.trusted_oauth_apps_owner,
          name: "GitHub Codespaces",
          slug: "github-codespaces",
          url: "https://github.com",
          default_permissions: INTEGRATION_PERMISSONS,
          visibility: :public_visibility,
          skip_restrict_names_with_github_validation: true,
          skip_generate_slug: true,
          no_repo_permissions_allowed: false,
          device_flow_enabled: false,
        }
        app = Integration.find_by(key: GitHub.codespaces_app_key)

        if app.nil?
          puts "Creating Codespaces app..."
          # Use minimal permissions until after we've enabled the resource-specific feature flags on the app
          app = Integration.create!(**properties, default_permissions: { "metadata" => :read })
          GitHub.flipper[:pull_requests_comment_only_reviews_resource].enable(app)
          GitHub.flipper[:pull_requests_from_forks_resource].enable(app)
          app.update!(default_permissions: INTEGRATION_PERMISSONS)
        else
          puts "Updating existing Codespaces app..."
          app.update!(**properties)
        end
      end

      def self.update_vscode_oauth_app!
        properties = {
          key: VSCODE_AUTH_SERVER_KEY,
          user: GitHub.trusted_oauth_apps_owner,
          name: "GitHub for VS Code",
          description: "It's your workflow but better, when GitHub and Visual Studio Code work together.",
          url: "https://vscode.github.com",
          callback_url: "https://vscode-auth.github.com/",
          device_flow_enabled: true,
        }
        app = OauthApplication.find_by(key: VSCODE_AUTH_SERVER_KEY)

        if app.nil?
          puts "Creating VS Code OAuth app..."
          app = OauthApplication.create!(**properties)
          app.client_secrets.create!(creator: User.ghost, **VSCODE_OAUTH_APP_SECRET)
        else
          puts "Updating existing VS Code OAuth app..."
          app.update!(**properties)

          if !app.client_secrets.exists?(**VSCODE_OAUTH_APP_SECRET)
            app.client_secrets.create!(creator: User.ghost, **VSCODE_OAUTH_APP_SECRET)
          end
        end

        app.set_application_callback_urls([
          "https://vscode-auth.github.com/",
          "https://insiders.vscode.dev/redirect",
          "https://vscode.dev/redirect",
        ])
        app.save!
      end

      def self.update_jetbrains_app!
        properties = {
          key: JETBRAINS_KEY,
          user: GitHub.trusted_oauth_apps_owner,
          name: "GitHub Codespaces for JetBrains",
          description: "Codespaces integration for JetBrains Gateway and IDEs.",
          url: "https://github.com/features/codespaces",
          callback_url: "https://github.com/features/codespaces",
          device_flow_enabled: true,
        }
        app = OauthApplication.find_by(key: JETBRAINS_KEY)

        if app.nil?
          puts "Creating JetBrains app..."
          app = OauthApplication.create!(**properties)
        else
          puts "Updating existing JetBrains app..."
          app.update!(**properties)
        end
      end

      def self.find_or_create_plan!(name: nil, location:, vscs_target:, business_id:)
        plan = ::Codespaces::Plan.find_by(location:, vscs_target:, business_id:)
        if plan && (plan.name == name || name.nil?)
          # plan already exists, use it & return early
          puts "Found plan #{plan.name}, skipping..."
          return plan
        end

        plan = ::Codespaces::Plan.create!(name:, location:, vscs_target:, business_id:)
        puts "Created plan #{plan.name}"
        plan
      end

      def self.seed_plans!(tenant_slug: nil)
        environment = GitHub.multi_tenant_enterprise? ? "tenants" : "dotcom"

        # Until we remove the index and validation on ::Plan#name we can't create canonical plans with the same name for every possible tenant
        # So for now we create plans for a single tenant at a time
        business = Business.find_by(slug: tenant_slug || "avocado-gmbh") if GitHub.multi_tenant_enterprise?
        business_id = business&.id

        puts "Creating plans for #{environment} and business: #{business&.slug || 'dotcom'}..."

        ::Codespaces::Plan.all.update_all(business_id: business_id)

        DEV_PLANS.each do |vscs_target, config|
          config.each do |location, plan|
            find_or_create_plan!(name: plan[:name], location:, vscs_target:, business_id: business_id)
          end
        end

      end

      def self.visual_studio_app_ids
        @visual_studio_app_ids ||= Apps::Privileged.oauth_application_ids([:visual_studio]).values.compact
      end
    end
  end
end
