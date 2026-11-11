# typed: true
# frozen_string_literal: true

class CreateJanitorSweeperEntityConfig < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Spokes)

  def change
    create_table :janitor_sweeper_entity_config, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :repository_id, unsigned: true, null: false
      t.integer :repository_type, null: false
      t.boolean :ignored, null: false, default: false
      t.timestamps

      t.index [:repository_id, :repository_type], unique: true, name: "index_janitor_sweeper_entity_config_on_repo_id_and_type"
    end
  end
end
