# typed: true

class AddIndexOnOwnerIdAndActiveCachesSizeToActionsCacheUsages < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Billing)
  def change
    change_table :actions_cache_usages, bulk: true do |t|
      t.index [:owner_id, :active_caches_size], name: "index_actions_cache_usages_on_owner_id_and_active_caches_size"
      t.remove_index name: "index_actions_cache_usages_on_owner_id"
    end
  end
end
