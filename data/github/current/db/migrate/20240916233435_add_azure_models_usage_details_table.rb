# typed: true
# frozen_string_literal: true

class AddAzureModelsUsageDetailsTable < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Integrations)

  def change
    create_table :azure_models_usage_details, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :auths_count, :bigint, unsigned: true, null: false
      t.column :user_id, :bigint, unsigned: true, index: { unique: true }, null: false
      t.timestamps
    end
  end
end
