# typed: true

class CreateGitHubModelsPublishers < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::GitHubModels)

  def change
    create_table :models_publishers, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.string :name, null: false
      t.text :logo_url
      t.blob :dark_mode_icon
      t.blob :light_mode_icon
      t.timestamps

      t.index :name, unique: true
    end
  end
end
