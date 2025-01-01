# typed: true
class AddIntegrationInstallationIdToGates < ActiveRecord::Migration[7.1]

  self.use_connection_class(ApplicationRecord::Repositories)

  def up
    change_table :gates, bulk: true do |t|
      t.references :integration_installation, type: :bigint, unsigned: true, null: true
    end
  end

  def down
    change_table :gates, bulk: true do |t|
      t.remove :integration_installation_id
    end
  end
end
