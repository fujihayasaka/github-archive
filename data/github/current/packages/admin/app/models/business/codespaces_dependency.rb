# typed: true
# frozen_string_literal: true

module Business::CodespacesDependency
  extend T::Helpers
  requires_ancestor { Business }
  include Vexi::Actor

  def free_codespace_use_enabled?
    self.feature_flag_enabled?(:codespaces_billing_free, default: false)
  end

  sig { returns(T::Boolean) }
  def billing_v_next_enabled_for_codespaces?
    true
  end

  # Gates Salus Private Beta features, targeting specific enterprises
  # Customer must be in the codespaces_salus_beta_customers feature flag AND
  # the specific feature may have a killswitch flag that gates the feature
  def in_codespaces_salus_beta?
    self.feature_flag_enabled?(:codespaces_salus_beta_customers, default: false)
  end

  # Enables vnets but not all of Salus features
  # This bypasses the salus flag for the vnet injection feature
  def in_vnet_only_beta?
    self.feature_flag_enabled?(:codespaces_vnet_only_beta, default: false)
  end
end
