# typed: true

class AddIndexCreatedAtIntegrationInstallations < ActiveRecord::Migration[7.1]
  def change
    add_index :integration_installations, [:integration_id, :created_at], name: "index_integration_id_and_created_at"
  end
end
