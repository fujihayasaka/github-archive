class RemoveEarlyAccessMembershipsUniqueMemberIdFeatureSlugIndex < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def up
    change_table :early_access_memberships, bulk: true do |t|
      # Remove unused indices
      if index_exists?(:early_access_memberships, [:member_id, :member_type], name: "index_early_access_memberships_on_member_id_and_member_type")
        t.remove_index [:member_id, :member_type], name: "index_early_access_memberships_on_member_id_and_member_type"
      end

      if index_exists?(:early_access_memberships, :member_type, name: "index_early_access_memberships_on_user_id_and_member_type")
        t.remove_index [:member_type], name: "index_early_access_memberships_on_user_id_and_member_type"
      end

      # Convert unique index to non-unique
      if index_exists?(:early_access_memberships, [:member_id, :member_type, :feature_slug], name: "idx_early_access_memberships_member_id_member_type_feature_slug", unique: true)
        t.remove_index [:member_id, :member_type, :feature_slug], name: "idx_early_access_memberships_member_id_member_type_feature_slug", unique: true
        t.index [:member_id, :member_type, :feature_slug], name: "idx_early_access_memberships_member_id_member_type_feature_slug"
      end
    end
  end

  def down
    change_table :early_access_memberships, bulk: true do |t|
      unless index_exists?(:early_access_memberships, [:member_id, :member_type], name: "index_early_access_memberships_on_member_id_and_member_type")
        t.index [:member_id, :member_type], name: "index_early_access_memberships_on_member_id_and_member_type"
      end

      unless index_exists?(:early_access_memberships, :member_type, name: "index_early_access_memberships_on_user_id_and_member_type")
        t.index [:member_type], name: "index_early_access_memberships_on_user_id_and_member_type"
      end

      unless index_exists?(:early_access_memberships, [:member_id, :member_type, :feature_slug], name: "idx_early_access_memberships_member_id_member_type_feature_slug", unique: true)
        t.remove_index [:member_id, :member_type, :feature_slug], name: "idx_early_access_memberships_member_id_member_type_feature_slug"
        t.index [:member_id, :member_type, :feature_slug], name: "idx_early_access_memberships_member_id_member_type_feature_slug", unique: true
      end
    end
  end
end
