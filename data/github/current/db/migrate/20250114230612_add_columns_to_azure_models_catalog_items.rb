# typed: true

class AddColumnsToAzureModelsCatalogItems < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Integrations)

  def change
    change_table :azure_models_catalog_items, bulk: true do |t|
      t.string :guid, limit: 150
      t.string :name, limit: 60
      t.string :original_name, limit: 60
      t.string :friendly_name, limit: 60
      t.integer :source, default: 0
      t.string :task, limit: 30
      t.string :license, limit: 60
      t.text :description
      t.text :summary
      t.string :model_family, limit: 30
      t.string :model_version, limit: 30
      t.text :notes
      t.text :tags
      t.string :rate_limit_tier, limit: 60
      t.text :supported_languages
      t.column :max_output_tokens, :integer
      t.column :max_input_tokens, :integer
      t.date :training_data_date
      t.text :evaluation
      t.text :license_description
      t.boolean :static_model, null: false, default: false
      t.text :supported_input_modalities
      t.text :supported_output_modalities
      t.text :schema
      t.column :github_models_publisher_id, :bigint, unsigned: true
      t.column :popularity, :float, default: 0, null: false
    end
  end
end
