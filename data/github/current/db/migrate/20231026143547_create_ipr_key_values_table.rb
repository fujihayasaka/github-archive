# rubocop:disable GitHub/UseBigintUnsignedPrimaryKeys

class CreateIprKeyValuesTable < ActiveRecord::Migration[7.2]
  use_connection_class ApplicationRecord::IssuesPullRequests

  def change
    create_table :ipr_key_values, primary_key: [:repository_id, :key], charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.string :key, null: false
      t.bigint :repository_id, null: false, unsigned: true
      t.binary :value, null: false
      t.datetime :expires_at, null: true, precision: 6
      t.timestamps null: false
    end

    add_index :ipr_key_values, :expires_at
    add_vindex :ipr_key_values, :hash, :repository_id
  end
end
