# typed: true

# rubocop:disable GitHub/UseBigintUnsignedPrimaryKeys
class ConvertSecurityConfigurationsToSignedBigint < ActiveRecord::Migration[8.0]
  use_connection_class ApplicationRecord::Domain::RepositoriesNotify

  def change
    change_table :security_configurations, bulk: true do |t|
      t.change :id, :bigint, unsigned: false
      t.change :target_id, :bigint, unsigned: false

      t.change :code_scanning, :integer, limit: 1, after: :enable_ghas
      t.change :dependabot_alerts, :integer, limit: 1, after: :code_scanning
      t.change :dependabot_security_updates, :integer, limit: 1, after: :dependabot_alerts
      t.change :dependency_graph_autosubmit_action, :integer, limit: 1, after: :dependabot_security_updates
      t.change :dependency_graph_autosubmit_action_options, :json, after: :dependency_graph_autosubmit_action
      t.change :dependency_graph, :integer, limit: 1, after: :dependency_graph_autosubmit_action_options
      t.change :private_vulnerability_reporting, :integer, limit: 1, after: :dependency_graph
      t.change :secret_scanning, :integer, limit: 1, after: :private_vulnerability_reporting
      t.change :secret_scanning_delegated_bypass, :integer, limit: 1, after: :secret_scanning
      t.change :secret_scanning_non_provider_patterns, :integer, limit: 1, after: :secret_scanning_delegated_bypass
      t.change :secret_scanning_push_protection, :integer, limit: 1, after: :secret_scanning_non_provider_patterns
      t.change :secret_scanning_validity_checks, :integer, limit: 1, after: :secret_scanning_push_protection
    end
  end
end
