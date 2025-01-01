# typed: true

# rubocop:disable GitHub/UseBigintUnsignedPrimaryKeys
class ConvertRepositorySecurityConfigurationsToSignedBigint < ActiveRecord::Migration[8.0]
  use_connection_class ApplicationRecord::Domain::RepositoriesNotify

  def change
    change_table :repository_security_configurations, bulk: true do |t|
      t.change :id, :bigint, unsigned: false
      t.change :security_configuration_id, :bigint, unsigned: false
      t.change :repository_id, :bigint, unsigned: false
      t.change :organization_id, :bigint, unsigned: false, after: :repository_id
      t.change :state, :integer, limit: 1, unsigned: false
    end
  end
end
