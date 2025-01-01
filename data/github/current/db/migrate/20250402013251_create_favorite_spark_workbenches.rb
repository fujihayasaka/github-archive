# typed: true
# frozen_string_literal: true

class CreateFavoriteSparkWorkbenches < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    create_table :favorite_spark_workbenches, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :user_id, :bigint, null: false, unsigned: true
      t.column :spark_workbench_id, :bigint, null: false, unsigned: true
      t.timestamps

      t.index :user_id, name: "index_favorite_spark_workbenches_on_user_id"
      t.index :spark_workbench_id, name: "index_favorite_spark_workbenches_on_spark_workbench_id"
    end
  end
end
