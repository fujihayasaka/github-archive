class CreateKeyValuesTable < ActiveRecord::Migration[6.0]
  def self.up
    create_table :dg_key_values, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci" do |t|
      t.string :key, null: false
      t.binary :value, null: false
      t.datetime :expires_at, null: true
      t.timestamps null: false
    end

    add_index  :dg_key_values, :key, unique: true
    add_index  :dg_key_values, :expires_at

    change_column  :dg_key_values, :id, "bigint(20) NOT NULL AUTO_INCREMENT"
  end

  def self.down
    drop_table  :dg_key_values
  end
end
