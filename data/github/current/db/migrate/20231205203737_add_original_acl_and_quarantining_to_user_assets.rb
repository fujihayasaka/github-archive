# typed: true

class AddOriginalAclAndQuarantiningToUserAssets < ActiveRecord::Migration[7.2]
  def change
    change_table :user_assets, bulk: true do |t|
      t.column :original_acl, :string, default: nil
      t.column :quarantining, :boolean, null: true, default: nil
      t.index [:quarantining]

      t.change :id, :bigint, unsigned: true
      t.change :user_id, :bigint, unsigned: true
      t.change :storage_blob_id, :bigint, unsigned: true
    end
  end
end
