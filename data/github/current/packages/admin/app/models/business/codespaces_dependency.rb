# typed: true
# frozen_string_literal: true

module Business::CodespacesDependency
  extend T::Helpers
  requires_ancestor { Business }

  def free_codespace_use_enabled?
    self.feature_enabled?(:codespaces_billing_free)
  end

  sig { returns(T::Boolean) }
  def billing_v_next_enabled_for_codespaces?
    return true if ::FeatureFlag.vexi.enabled?(:cutoff_emissions_to_meuse, default: false)
    !!billing_customer&.billing_platform_enabled_product&.codespaces?
  end

  # Gates Salus Private Beta features, targeting specific enterprises
  # Customer must be in the codespaces_salus_beta_customers feature flag AND
  # the specific feature may have a killswitch flag that gates the feature
  def in_codespaces_salus_beta?
    self.feature_enabled?(:codespaces_salus_beta_customers)
  end

  # Enables vnets but not all of Salus features
  # This bypasses the salus flag for the vnet injection feature
  def in_vnet_only_beta?
    self.feature_enabled?(:codespaces_vnet_only_beta)
  end
end
