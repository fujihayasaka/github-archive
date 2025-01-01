# typed: true
# frozen_string_literal: true

class AddCodeSecurityEnablementStrategyToLicensingModelTransition < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Billing)

  def change
    add_column :licensing_model_transitions, :code_security_enablement_strategy, :integer, limit: 1, default: 1
  end
end
