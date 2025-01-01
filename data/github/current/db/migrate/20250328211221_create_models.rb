# typed: true

class CreateModels < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::GitHubModels)

  def change
    create_table :models, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.string :slug, limit: 80, null: false
      t.column :value, :json, null: false
      t.integer :visibility, default: 0, null: false
      t.column :has_free_playground, :boolean, null: false, default: false
      t.string :name, limit: 60
      t.string :original_name, limit: 60
      t.string :friendly_name, limit: 60
      t.integer :source, default: 0
      t.string :task, limit: 30
      t.string :license, limit: 60
      t.text :description
      t.text :summary
      t.string :version, limit: 30
      t.text :notes
      t.text :tags
      t.string :rate_limit_tier, limit: 60
      t.text :supported_languages
      t.column :max_output_tokens, :integer
      t.column :max_input_tokens, :integer
      t.date :training_data_date
      t.text :evaluation
      t.text :license_description
      t.text :supported_input_modalities
      t.text :supported_output_modalities
      t.text :model_schema
      t.column :models_publisher_id, :bigint, unsigned: true
      t.column :popularity, :float, default: 0, null: false

      t.timestamps

      t.index :slug, unique: true
      t.index [:visibility, :slug]
      t.index [:has_free_playground, :visibility]
      t.index :models_publisher_id
    end
  end
end
