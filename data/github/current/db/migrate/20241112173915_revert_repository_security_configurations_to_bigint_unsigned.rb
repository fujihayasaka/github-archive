# typed: true

class RevertRepositorySecurityConfigurationsToBigintUnsigned < ActiveRecord::Migration[8.0]
  use_connection_class ApplicationRecord::Domain::RepositoriesNotify

  def change
    change_table :repository_security_configurations, bulk: true do |t|
      t.change :id, :bigint, unsigned: true
      t.change :security_configuration_id, :bigint, unsigned: true
      t.change :repository_id, :bigint, unsigned: true
      t.change :organization_id, :bigint, unsigned: true
    end
  end
end
