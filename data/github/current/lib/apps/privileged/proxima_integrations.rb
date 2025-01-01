# typed: true
# frozen_string_literal: true

module Apps
  class Privileged
    class ProximaIntegrations
      ACTIONS_RESOLVER_WEU1_APP_NAME = "Proxima Actions Resolver weu1"
      ACTIONS_RESOLVER_WUS2_1_APP_NAME = "Proxima Actions Resolver wus2-1"
      ACTIONS_RESOLVER_SDC1_APP_NAME = "Proxima Actions Resolver sdc1"
      ACTIONS_RESOLVER_AE1_APP_NAME = "Proxima Actions Resolver ae1"
      ACTIONS_RESOLVER_CUS1_APP_NAME = "Proxima Actions Resolver cus1"
      ACTIONS_RESOLVER_CNC1_APP_NAME = "Proxima Actions Resolver cnc1"
      ACTIONS_TEMPLATE_LOADER_WEU1_APP_NAME = "Proxima Actions Templates weu1"
      ACTIONS_TEMPLATE_LOADER_WUS2_1_APP_NAME = "Proxima Actions Templates wus2-1"
      ACTIONS_TEMPLATE_LOADER_SDC1_APP_NAME = "Proxima Actions Templates sdc1"
      ACTIONS_TEMPLATE_LOADER_AE1_APP_NAME = "Proxima Actions Templates ae1"
      ACTIONS_TEMPLATE_LOADER_CUS1_APP_NAME = "Proxima Actions Templates cus1"
      ADVISORY_DATABASE_WEU_1_APP_NAME = "Proxima Advisory Database weu-1"
      ADVISORY_DATABASE_WUS2_1_APP_NAME = "Proxima Advisory Database wus2-1"
      ADVISORY_DATABASE_SDC1_APP_NAME = "Proxima Advisory Database sdc1"
      ADVISORY_DATABASE_AE1_APP_NAME = "Proxima Advisory Database ae1"
      ADVISORY_DATABASE_CUS1_APP_NAME = "Proxima Advisory Database cus1"
      ADVISORY_DATABASE_CNC1_APP_NAME = "Proxima Advisory Database cnc1"
      DEPENDABOT_WEU_1_APP_NAME = "Proxima Dependabot weu-1"
      DEPENDABOT_WUS2_1_APP_NAME = "Proxima Dependabot wus2-1"

      ACTIONS_RESOLVER_WEU1 = {
        alias: :proxima_actions_resolver_weu1,
        database_lookup_attributes: { owner_id: :trusted_proxima_apps_owner_id, name: ACTIONS_RESOLVER_WEU1_APP_NAME },
        inherits: [:first_party],
        capabilities: {
          enforce_internal_access_on_token_generation: false,
          resolve_public_dotcom_actions_via_proxima_fallback: true,
        },
        properties: {},
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/c2c-actions"],
        available_on_ghes: false,
      }

      ACTIONS_RESOLVER_WUS2_1 = {
        alias: :proxima_actions_resolver_wus2_1,
        database_lookup_attributes: { owner_id: :trusted_proxima_apps_owner_id, name: ACTIONS_RESOLVER_WUS2_1_APP_NAME },
        inherits: [:first_party],
        capabilities: {
          enforce_internal_access_on_token_generation: false,
          resolve_public_dotcom_actions_via_proxima_fallback: true,
        },
        properties: {},
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/c2c-actions"],
        available_on_ghes: false,
      }

      ACTIONS_RESOLVER_SDC1 = {
        alias: :proxima_actions_resolver_sdc1,
        database_lookup_attributes: { owner_id: :trusted_proxima_apps_owner_id, name: ACTIONS_RESOLVER_SDC1_APP_NAME },
        inherits: [:first_party],
        capabilities: {
          enforce_internal_access_on_token_generation: false,
          resolve_public_dotcom_actions_via_proxima_fallback: true,
        },
        properties: {},
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/c2c-actions"],
        available_on_ghes: false,
      }

      ACTIONS_RESOLVER_AE1 = {
        alias: :proxima_actions_resolver_ae1,
        database_lookup_attributes: { owner_id: :trusted_proxima_apps_owner_id, name: ACTIONS_RESOLVER_AE1_APP_NAME },
        inherits: [:first_party],
        capabilities: {
          enforce_internal_access_on_token_generation: false,
          resolve_public_dotcom_actions_via_proxima_fallback: true,
        },
        properties: {},
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/c2c-actions"],
        available_on_ghes: false,
      }

      ACTIONS_RESOLVER_CUS1 = {
        alias: :proxima_actions_resolver_cus1,
        database_lookup_attributes: { owner_id: :trusted_proxima_apps_owner_id, name: ACTIONS_RESOLVER_CUS1_APP_NAME },
        inherits: [:first_party],
        capabilities: {
          enforce_internal_access_on_token_generation: false,
          resolve_public_dotcom_actions_via_proxima_fallback: true,
        },
        properties: {},
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/c2c-actions"],
        available_on_ghes: false,
      }

      ACTIONS_RESOLVER_CNC1 = {
        alias: :proxima_actions_resolver_cnc1,
        database_lookup_attributes: { owner_id: :trusted_proxima_apps_owner_id, name: ACTIONS_RESOLVER_CNC1_APP_NAME },
        inherits: [:first_party],
        capabilities: {
          enforce_internal_access_on_token_generation: false,
          resolve_public_dotcom_actions_via_proxima_fallback: true,
        },
        properties: {},
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/c2c-actions"],
        available_on_ghes: false,
      }

      ACTIONS_RESOLVER_PERMISSIONS = {
        "actions" => :read,
      }

      ACTIONS_TEMPLATE_LOADER_WEU1 = {
        alias: :proxima_actions_template_loader_weu1,
        database_lookup_attributes: { owner_id: :trusted_proxima_apps_owner_id, name: ACTIONS_TEMPLATE_LOADER_WEU1_APP_NAME },
        inherits: [:first_party],
        capabilities: {
          enforce_internal_access_on_token_generation: false,
        },
        properties: {},
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/c2c-actions"],
        available_on_ghes: false,
      }

      ACTIONS_TEMPLATE_LOADER_WUS2_1 = {
        alias: :proxima_actions_template_loader_wus2_1,
        database_lookup_attributes: { owner_id: :trusted_proxima_apps_owner_id, name: ACTIONS_TEMPLATE_LOADER_WUS2_1_APP_NAME },
        inherits: [:first_party],
        capabilities: {
          enforce_internal_access_on_token_generation: false,
        },
        properties: {},
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/c2c-actions"],
        available_on_ghes: false,
      }

      ACTIONS_TEMPLATE_LOADER_SDC1 = {
        alias: :proxima_actions_template_loader_sdc1,
        database_lookup_attributes: { owner_id: :trusted_proxima_apps_owner_id, name: ACTIONS_TEMPLATE_LOADER_SDC1_APP_NAME },
        inherits: [:first_party],
        capabilities: {
          enforce_internal_access_on_token_generation: false,
        },
        properties: {},
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/c2c-actions"],
        available_on_ghes: false,
      }

      ACTIONS_TEMPLATE_LOADER_AE1 = {
        alias: :proxima_actions_template_loader_ae1,
        database_lookup_attributes: { owner_id: :trusted_proxima_apps_owner_id, name: ACTIONS_TEMPLATE_LOADER_AE1_APP_NAME },
        inherits: [:internal],
        capabilities: {
          enforce_internal_access_on_token_generation: false,
        },
        properties: {},
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/c2c-actions"],
        available_on_ghes: false,
      }

      ACTIONS_TEMPLATE_LOADER_CUS1 = {
        alias: :proxima_actions_template_loader_cus1,
        database_lookup_attributes: { owner_id: :trusted_proxima_apps_owner_id, name: ACTIONS_TEMPLATE_LOADER_CUS1_APP_NAME },
        inherits: [:internal],
        capabilities: {
          enforce_internal_access_on_token_generation: false,
        },
        properties: {},
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/c2c-actions"],
        available_on_ghes: false,
      }

      ACTIONS_TEMPLATE_LOADER_PERMISSIONS = {
        "actions" => :read,
      }

      ADVISORY_DATABASE_WEU_1 = {
        alias: :proxima_advisory_database_weu_1,
        database_lookup_attributes: { owner_id: :trusted_proxima_apps_owner_id, name: ADVISORY_DATABASE_WEU_1_APP_NAME },
        inherits: [:first_party],
        capabilities: {
          enforce_internal_access_on_token_generation: false,
          internal_advisory_database: true,
        },
        properties: {},
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/advisory-database"],
        available_on_ghes: false,
      }

      ADVISORY_DATABASE_WUS2_1 = {
        alias: :proxima_advisory_database_wus2_1,
        database_lookup_attributes: { owner_id: :trusted_proxima_apps_owner_id, name: ADVISORY_DATABASE_WUS2_1_APP_NAME },
        inherits: [:first_party],
        capabilities: {
          enforce_internal_access_on_token_generation: false,
          internal_advisory_database: true,
        },
        properties: {},
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/advisory-database"],
        available_on_ghes: false,
      }

      ADVISORY_DATABASE_SDC1 = {
        alias: :proxima_advisory_database_sdc1,
        database_lookup_attributes: { owner_id: :trusted_proxima_apps_owner_id, name: ADVISORY_DATABASE_SDC1_APP_NAME },
        inherits: [:first_party],
        capabilities: {
          enforce_internal_access_on_token_generation: false,
          internal_advisory_database: true,
        },
        properties: {},
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/advisory-database"],
        available_on_ghes: false,
      }

      ADVISORY_DATABASE_AE1 = {
        alias: :proxima_advisory_database_ae1,
        database_lookup_attributes: { owner_id: :trusted_proxima_apps_owner_id, name: ADVISORY_DATABASE_AE1_APP_NAME },
        inherits: [:first_party],
        capabilities: {
          enforce_internal_access_on_token_generation: false,
          internal_advisory_database: true,
        },
        properties: {},
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/advisory-database"],
        available_on_ghes: false,
      }

      ADVISORY_DATABASE_CUS1 = {
        alias: :proxima_advisory_database_cus1,
        database_lookup_attributes: { owner_id: :trusted_proxima_apps_owner_id, name: ADVISORY_DATABASE_CUS1_APP_NAME },
        inherits: [:first_party],
        capabilities: {
          enforce_internal_access_on_token_generation: false,
          internal_advisory_database: true,
        },
        properties: {},
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/advisory-database"],
        available_on_ghes: false,
      }

      ADVISORY_DATABASE_CNC1 = {
        alias: :proxima_advisory_database_cnc1,
        database_lookup_attributes: { owner_id: :trusted_proxima_apps_owner_id, name: ADVISORY_DATABASE_CNC1_APP_NAME },
        inherits: [:first_party],
        capabilities: {
          enforce_internal_access_on_token_generation: false,
          internal_advisory_database: true,
        },
        properties: {},
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/advisory-database"],
        available_on_ghes: false,
      }

      DEPENDABOT_PROXIMA_PERMISSIONS = {
        "contents"             => :read,
        "issues"               => :read,
        "metadata"             => :read,
      }

      DEPENDABOT_WEU_1 = {
        alias: :proxima_dependabot_weu_1,
        database_lookup_attributes: { owner_id: :trusted_proxima_apps_owner_id, name: DEPENDABOT_WEU_1_APP_NAME },
        inherits: [:first_party],
        capabilities: {
          enforce_internal_access_on_token_generation: false,
        },
        properties: {},
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/dependabot-api"],
        available_on_ghes: false,
      }

      DEPENDABOT_WUS2_1 = {
        alias: :proxima_dependabot_wus2_1,
        database_lookup_attributes: { owner_id: :trusted_proxima_apps_owner_id, name: DEPENDABOT_WUS2_1_APP_NAME },
        inherits: [:first_party],
        capabilities: {
          enforce_internal_access_on_token_generation: false,
        },
        properties: {},
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/dependabot-api"],
        available_on_ghes: false,
      }
    end
  end
end
