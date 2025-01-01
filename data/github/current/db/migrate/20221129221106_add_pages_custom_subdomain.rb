# typed: true

class AddPagesCustomSubdomain < ActiveRecord::Migration[7.1]
  # rubocop:todo GitHub/EnsureDomainIsolationInMigration (can be dropped once table move completed)
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    change_table :pages, bulk: true do |t|
      t.column :custom_subdomain, "varchar(96)", null: true, comment: "custom_subdomain is 63 characters + _{tenant shortcode}"
      t.index :custom_subdomain, unique: true, name: "index_pages_on_unique_custom_subdomain"
    end
  end
end
