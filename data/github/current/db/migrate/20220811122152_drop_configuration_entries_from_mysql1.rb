# typed: true
class DropConfigurationEntriesFromMysql1 < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Mysql1)

  def up
    return if GitHub.enterprise? || Rails.env.production?

    drop_table :configuration_entries, if_exists: true
  end

  def down
    return if GitHub.enterprise? || Rails.env.production?

    create_table :configuration_entries, id: :integer, charset: "utf8"  do |t|
      t.integer :target_id, null: false
      t.string :target_type, null: false, limit: 30
      t.integer :updater_id, null: false
      t.string :name, null: false, limit: 80
      t.string :value, null: false, limit: 255
      t.boolean :final, null: false, default: false
      t.datetime :created_at, null: false, precision: nil
      t.datetime :updated_at, null: false, precision: nil
      t.index [:target_id, :target_type, :name], unique: true, name: "index_configuration_entries_on_target_and_name"
      t.index [:target_type, :target_id, :name, :value, :final], name: "index_on_target_type_and_target_id_and_name_and_value_and_final"
      t.index [:name, :target_type, :value], name: "index_configuration_entries_on_name_and_target_type_and_value"
    end
  end
end
