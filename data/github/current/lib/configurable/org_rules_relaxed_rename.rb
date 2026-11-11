# typed: true
# frozen_string_literal: true

# Configures whether to allow relaxed renames of organization-protected branches
module Configurable
  module OrgRulesRelaxedRename
    extend T::Helpers

    requires_ancestor { Object }
    requires_ancestor { Configurable }

    KEY = "org_rules_relaxed_rename".freeze

    # Enable relaxed renames for organization.
    def enable_org_rules_relaxed_rename(actor:)
      raise ArgumentError, "Can only be configured on an Organization" unless self.is_a?(Organization)

      if FeatureFlag.vexi.enabled?(:org_rules_relaxed_rename, self, default: false)
        config.enable(KEY, actor)
      end
    end

    # Disable relaxed renames for organization.
    def disable_org_rules_relaxed_rename(actor:)
      raise ArgumentError, "Can only be configured on an Organization" unless self.is_a?(Organization)
      config.delete(KEY, actor)
    end

    # Determines whether relaxed rename behavior for organization-protected branches is enabled for this organization.
    def org_rules_relaxed_rename_enabled?
      self.is_a?(Organization) && config.enabled?(KEY) && FeatureFlag.vexi.enabled?(:org_rules_relaxed_rename, self, default: false)
    end

    # Initialize relaxed rename for newly created organizations. Called via after_create callback on Organization.
    # The feature flag gate inside enable_org_rules_relaxed_rename ensures this is a no-op until the feature is
    # publicly rolled out. Orgs created after that time will default to relaxed rename semantics; existing orgs will
    # have to opt-in to the new behavior.
    def initialize_org_rules_relaxed_rename
      enable_org_rules_relaxed_rename(actor: self)
    end
  end
end
