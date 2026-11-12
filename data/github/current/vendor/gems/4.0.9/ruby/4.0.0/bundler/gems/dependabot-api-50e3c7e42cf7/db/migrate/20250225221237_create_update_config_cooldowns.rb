# frozen_string_literal: true

class CreateUpdateConfigCooldowns < ActiveRecord::Migration[7.0]
  def change
    create_table :update_config_cooldowns, id: :bigint, unsigned: true, auto_increment: true, charset: "utf8mb4", collation: "utf8mb4_general_ci" do |t|
      t.bigint :update_config_id, unsigned: true
      # Cooldown periods in days for different version updates
      t.integer :default_days, null: false, default: 0 # applies to all version updates
      t.integer :semver_major_days, null: false, default: 0  # applies delay to major version updates
      t.integer :semver_minor_days, null: false, default: 0  # applies delay to minor version updates
      t.integer :semver_patch_days, null: false, default: 0  # applies delay to patch version updates
      # Lists of dependencies for cooldown enforcement
      t.json :include, null: true # array of dependency names patterns to include
      t.json :exclude, null: true # array of dependency names patterns to exclude

      t.timestamps

      t.index :update_config_id, name: "index_update_config_cooldowns_on_config_id"
    end
  end
end
