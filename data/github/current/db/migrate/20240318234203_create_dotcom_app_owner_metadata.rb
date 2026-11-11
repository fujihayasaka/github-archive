class CreateDotcomAppOwnerMetadata < ActiveRecord::Migration[7.2]
  def change
    create_table :dotcom_app_owner_metadata, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.timestamps

      t.bigint :dotcom_id, unsigned: true, null: false
      t.string :dotcom_type, limit: 20, null: false
      t.string :dotcom_node_id, limit: 40, null: false

      t.string :login, limit: 40, null: false
      t.string :display_login, limit: 40, null: false
      t.text   :url, null: false
      t.text   :avatar_url, null: :true

      t.bigint :local_app_id, unsigned: true, null: false
      t.string :local_app_type, limit: 20, null: false

      t.index [:local_app_id, :local_app_type], unique: true, name: "index_dotcom_app_owner_metadata_on_local_app_id_and_type"
    end
  end
end
