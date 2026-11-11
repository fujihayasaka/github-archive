class AddCopilotRequiredAuthorizationsTable < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    create_table :copilot_required_authorizations, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.references :owner, polymorphic: true, index: { unique: false }, null: false
      t.column :reason, :string, null: false, limit: 1024
      t.timestamps
    end
  end
end
