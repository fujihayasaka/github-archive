# typed: true

class RevertSecurityConfigurationsToBigintUnsigned < ActiveRecord::Migration[8.0]
  use_connection_class ApplicationRecord::Domain::RepositoriesNotify

  def change
    change_table :security_configurations, bulk: true do |t|
      t.change :id, :bigint, unsigned: true
      t.change :target_id, :bigint, unsigned: true

      # Fly-by improvements
      t.change :dependency_graph, :integer, limit: 1, after: :dependabot_security_updates
      t.change :secret_scanning_generic_secrets, :integer, limit: 1, unsigned: false, after: :secret_scanning_delegated_bypass
      t.change :code_scanning_options, :json, after: :code_scanning
    end
  end
end
