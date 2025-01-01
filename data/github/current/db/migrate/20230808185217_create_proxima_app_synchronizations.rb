# typed: true

class CreateProximaAppSynchronizations < ActiveRecord::Migration[7.1]
  def change
    create_table :proxima_app_synchronizations, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.string :dotcom_global_id, limit: 40
      t.bigint :local_app_id, unsigned: true
      t.string :local_app_type, limit: 20
      t.string :fingerprint, limit: 64

      t.timestamps

      t.index :dotcom_global_id, unique: true
      t.index [:local_app_id, :local_app_type], unique: true
    end
  end
end
