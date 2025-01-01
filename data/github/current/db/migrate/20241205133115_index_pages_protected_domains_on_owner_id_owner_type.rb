# typed: true

class IndexPagesProtectedDomainsOnOwnerIdOwnerType < ActiveRecord::Migration[8.1]
  # rubocop:todo GitHub/EnsureDomainIsolationInMigration (can be dropped once table move completed)
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    change_table :pages_protected_domains, bulk: true do |t|
      t.index [:owner_id, :owner_type], name: "index_pages_protected_domains_on_owner_id_owner_type"
    end
  end
end
