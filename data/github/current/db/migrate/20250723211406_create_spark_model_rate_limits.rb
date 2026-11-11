# typed: true
# frozen_string_literal: true

class CreateSparkModelRateLimits < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    create_table :spark_model_rate_limits, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :user_id, :bigint, null: false, unsigned: true
      t.column :model, :string, null: false, limit: 255
      t.timestamps
      t.index [:model, :created_at], name: "index_spark_model_rate_limits_on_model_and_created_at"
    end
  end
end
