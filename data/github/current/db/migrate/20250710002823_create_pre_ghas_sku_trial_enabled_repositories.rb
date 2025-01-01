# typed: true

class CreatePreGhasSKUTrialEnabledRepositories < ActiveRecord::Migration[8.1]
  self.use_connection_class ApplicationRecord::Domain::SecurityProductsEnablement

  def change
    create_table :pre_ghas_sku_trial_enabled_repositories, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :repository_id, unsigned: true, null: false
      t.bigint :target_id, unsigned: true, null: false
      t.string :target_type, null: false, limit: 30
      t.string :sku_name, null: false, limit: 80
      t.timestamps

      t.index [:target_id, :target_type, :sku_name, :repository_id], unique: true, name: "index_target_id_and_sku_name_and_repository_id"
    end
  end
end
