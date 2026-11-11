# typed: true
# frozen_string_literal: true

# Configures whether to allow relaxed renames of enterprise-protected branches
module Configurable
  module BusinessRulesRelaxedRename
    extend T::Helpers

    requires_ancestor { Object }
    requires_ancestor { Configurable }

    KEY = "business_rules_relaxed_rename".freeze

    # Enable relaxed renames for enterprise.
    def enable_business_rules_relaxed_rename(actor:)
      raise ArgumentError, "Can only be configured on a Business" unless self.is_a?(Business)

      if FeatureFlag.vexi.enabled?(:ent_rules_relaxed_rename, self, default: false)
        config.enable(KEY, actor)
      end
    end

    # Disable relaxed renames for enterprise.
    def disable_business_rules_relaxed_rename(actor:)
      raise ArgumentError, "Can only be configured on a Business" unless self.is_a?(Business)
      config.disable(KEY, actor)
    end

    # Determines whether relaxed rename behavior for enterprise-protected branches is enabled for this enterprise.
    # Uses a default-enabled tri-state: if the configurable has never been explicitly set, returns true (relaxed
    # is the default). Returns false only when an admin has explicitly disabled it.
    def business_rules_relaxed_rename_enabled?
      self.is_a?(Business) && config.get(KEY) != false && FeatureFlag.vexi.enabled?(:ent_rules_relaxed_rename, self, default: false)
    end
  end
end
