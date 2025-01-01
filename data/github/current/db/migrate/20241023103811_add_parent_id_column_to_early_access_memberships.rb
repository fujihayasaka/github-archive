# typed: true

class AddParentIdColumnToEarlyAccessMemberships < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def up
    change_table :early_access_memberships, bulk: true do |t|
      t.bigint :parent_id, unsigned: true, null: false, default: 0, comment: "the parent membership id"

      t.index [:parent_id, :feature_slug], name: "index_early_access_memberships_parent_id_feature_slug"
    end
  end

  def down
    change_table :early_access_memberships, bulk: true do |t|
      t.remove_index [:parent_id, :feature_slug], name: "index_early_access_memberships_parent_id_feature_slug"
      t.remove :parent_id
    end
  end
end
