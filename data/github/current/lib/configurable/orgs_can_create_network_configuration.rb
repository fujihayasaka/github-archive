# typed: true
# frozen_string_literal: true

# Can organizations in enterprises create network configurations?
#
# Disabled by default on new installations.
# See https://github.com/github/cps-network-service/issues/303
#
module Configurable
  module OrgsCanCreateNetworkConfiguration
    extend T::Helpers

    requires_ancestor { Configurable }

    KEY = "orgs_can_create_network_configuration".freeze

    # Default to disabled if the setting has never been set.
    DEFAULT_VALUE = false

    # actor is actually a User (the one making the change), but we can't
    # type it as such because lib shouldn't depend on app.
    sig { params(actor: T.untyped, enabled: T::Boolean).void }
    def set_network_configuration_creation_by_org(actor, enabled)
      if enabled
        config.enable(KEY, actor)
      else
        config.disable(KEY, actor)
      end
    end

    sig { returns(T::Boolean) }
    def network_configuration_creation_by_org_enabled?
      return DEFAULT_VALUE if config.get(KEY).nil?
      config.enabled?(KEY)
    end
  end
end
