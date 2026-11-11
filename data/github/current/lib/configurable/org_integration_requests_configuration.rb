# typed: true
# frozen_string_literal: true

# Configures whether or not org members and outside collaborators can request installation of OAuth and GitHub Apps
module Configurable
  module OrgIntegrationRequestsConfiguration
    extend T::Helpers

    requires_ancestor { Configurable }
    requires_ancestor { Instrumentation::Model }
    requires_ancestor { GitHub::VexiActor }

    ALLOW_ALL = "allow_all".freeze # default. allow requests from outside collaborators and org members
    ALLOW_ORG_MEMBERS_ONLY = "allow_org_members_only".freeze # Outside collaborators cannot send requests, but org members can.
    DISABLED = "disabled".freeze # allows no requests.
    CONFIG_VALUES = [ALLOW_ALL, DISABLED, ALLOW_ORG_MEMBERS_ONLY].freeze
    DEFAULT_VALUE = ALLOW_ALL
    KEY = T.let("org_integration_requests_configuration", String)

    UNSUPPORTED_CONFIG_VALUE = "You provided an invalid config value. Please try again."
    class OrgIntegrationRequestsConfiguration < StandardError; end

    def update_org_integration_requests_configuration(actor: nil, config_value: nil)
      unless CONFIG_VALUES.include?(config_value)
        raise OrgIntegrationRequestsConfiguration.new UNSUPPORTED_CONFIG_VALUE
      end

      return unless config.set!(KEY, config_value, actor)
      instrument_org_integration_request_configuration_change(actor, config_value)
    end

    def allow_org_members_only_integration_requests(actor: nil)
      update_org_integration_requests_configuration(actor: actor, config_value: ALLOW_ORG_MEMBERS_ONLY)
    end

    def allow_all_integration_requests(actor: nil)
      update_org_integration_requests_configuration(actor: actor, config_value: ALLOW_ALL)
    end

    def disable_integration_requests(actor: nil)
      update_org_integration_requests_configuration(actor: actor, config_value: DISABLED)
    end

    def allows_members_only_integration_requests?
      config.get(KEY) == ALLOW_ORG_MEMBERS_ONLY
    end

    def allows_all_integration_requests?
      config.get(KEY) == DEFAULT_VALUE || config.get(KEY).nil?
    end

    def denies_all_integration_requests?
      config.get(KEY) == DISABLED
    end

    def denies_outside_collaborator_integration_requests?
      allows_members_only_integration_requests? || denies_all_integration_requests?
    end

    def org_integration_requests_configuration
      if config.get(KEY).nil?
        return DEFAULT_VALUE
      end
      config.get(KEY)
    end

    private

    def instrument_org_integration_request_configuration_change(actor, config_value)
      if self.feature_flag_enabled?(:expanded_integration_requests_setting, default: false)
        self.instrument("app_access_requests_configuration_update", {
          actor: actor,
          configuration_value: config_value
        })
      end
    end
  end
end
