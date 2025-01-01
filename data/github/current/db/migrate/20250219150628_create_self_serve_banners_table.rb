# typed: true

class CreateSelfServeBannersTable < ActiveRecord::Migration[8.1]
  use_connection_class ApplicationRecord::Domain::CopilotPLG

  def change
    create_table :self_serve_banners, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.string  :slug, limit: 100, null: false
      t.string  :body, limit: 1024
      t.string  :title, limit: 100
      t.text :cta_url
      t.string :cta_text, limit: 100
      t.integer :visibility, limit: 1, default: 0
      t.timestamps

      t.index :slug, unique: true
    end
  end
end
