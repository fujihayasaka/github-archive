class CreateCopilotIndexedRepositories < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  def change
    create_table :copilot_indexed_repositories, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :organization_id, :bigint, unsigned: true, null: true
      t.column :repository_id, :bigint, unsigned: true, null: false

      t.index :organization_id
      t.index :repository_id
      t.timestamps
    end
  end
end
