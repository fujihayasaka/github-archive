# typed: true
class CreateTopicSources < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::UsersBallast)

  def change
    create_table :topic_sources, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :topic_id, unsigned: true, null: false
      t.bigint :source_id, unsigned: true, null: false
      t.string :source_type, null: false
      t.string :slug, null: false

      t.timestamps
    end

    add_index :topic_sources, [:topic_id, :source_id, :source_type], unique: true
    add_index :topic_sources, [:source_id, :source_type]
  end
end
