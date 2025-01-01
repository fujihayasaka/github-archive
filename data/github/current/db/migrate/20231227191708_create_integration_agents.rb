class CreateIntegrationAgents < ActiveRecord::Migration[7.2]
  use_connection_class ApplicationRecord::Domain::Copilot

  def change
    create_table :integration_agents, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :integration_id, null: false, unsigned: true
      t.column :url, :text, null: false
      t.blob :description, null: false, index: false

      t.timestamps

      t.index :integration_id, unique: true
    end
  end
end
