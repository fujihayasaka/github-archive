# typed: true
# frozen_string_literal: true

class CreateSparkWorkbenches < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    create_table :spark_workbenches, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :user_id, :bigint, null: false, unsigned: true
      t.column :name, :string, null: true, limit: 255
      t.column :uuid, "BINARY(16)", null: false
      t.column :repository_id, :bigint, null: true, unsigned: true
      t.column :cloud_environment_id, :bigint, null: false, unsigned: true
      t.column :initialized, :boolean, null: false, default: false
      t.timestamps

      t.index :user_id, name: "index_spark_workbenches_on_user_id"
      t.index :repository_id, name: "index_spark_workbenches_on_repository_id"
      t.index :uuid, name: "index_spark_workbenches_on_uuid", unique: true
    end
  end
end
