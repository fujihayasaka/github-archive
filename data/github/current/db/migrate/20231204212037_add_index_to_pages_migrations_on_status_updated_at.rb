class AddIndexToPagesMigrationsOnStatusUpdatedAt < ActiveRecord::Migration[7.2]
  # rubocop:todo GitHub/EnsureDomainIsolationInMigration (can be dropped once table move completed)
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    change_table :pages_migrations, bulk: true do |t|
      t.index [:status, :updated_at], name: "index_status_updated_at_pages_migrations"
    end
  end
end
