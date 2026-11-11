# typed: true
# frozen_string_literal: true

class CreateAzureModelsPresets < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Integrations)

  def change
    create_table :azure_models_presets, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :user_id,              :bigint, unsigned: true, null: false
      t.column :url_identifier,       :string, index: { unique: true }, null: false
      t.column :name,                 :string, null: false
      t.column :description,          :string, null: true
      t.column :private,              :boolean, default: true, null: false
      t.column :conversation_history, :json, null: false
      t.column :parameters,           :json, null: false

      t.timestamps

      t.index [:user_id, :name], unique: true
    end
  end
end
