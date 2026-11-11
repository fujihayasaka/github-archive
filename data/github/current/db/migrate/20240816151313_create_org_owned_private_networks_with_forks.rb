class CreateOrgOwnedPrivateNetworksWithForks < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    create_table :org_owned_private_networks_with_forks, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :network_id, unsigned: true, null: false
      t.bigint :owner_id, unsigned: true, null: false

      t.timestamps null: false

      t.index [:network_id], name: "index_repos_oopnwf_on_network_id", unique: true
      t.index [:owner_id, :network_id], name: "index_repos_oopnwf_on_owner_id_and_network_id"
    end
  end
end
