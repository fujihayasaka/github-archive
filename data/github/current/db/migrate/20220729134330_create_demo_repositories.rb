# typed: true
class CreateDemoRepositories < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def change
    create_table :demo_repositories, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :repository_id, unsigned: true, null: false
      t.belongs_to :organization, type: :bigint, unsigned: true, null: false, index: { unique: true }

      t.timestamps
    end
  end
end
