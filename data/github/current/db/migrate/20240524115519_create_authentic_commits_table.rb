# rubocop:disable GitHub/UseBigintUnsignedPrimaryKeys
# typed: true

class CreateAuthenticCommitsTable < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::RepositoriesPushes)

  def change
    create_table :authentic_commits, primary_key: [:network_id, :oid], charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :network_id, :bigint, unsigned: true, null: false
      t.column :oid, "binary(20)", null: false
      t.column :verified_at, "datetime(6)", null: false
    end

    add_vindex :authentic_commits, :hash, :network_id
  end
end
