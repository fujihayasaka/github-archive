# typed: true
class CreateRepositoryRulesets < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    create_table :repository_rulesets, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.string :name, limit: 255
      t.bigint :source_id, unsigned: true, null: false
      t.string :source_type, limit: 100, null: false
      t.column :enforcement, "tinyint(3)", unsigned: true, null: false, default: 0
      t.timestamps

      t.index [:source_id, :source_type], name: "index_repository_rulesets_source"
    end
  end
end
