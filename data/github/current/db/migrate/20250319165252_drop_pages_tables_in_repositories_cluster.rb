# typed: true

# rubocop:disable GitHub/OneTablePerMigration

class DropPagesTablesInRepositoriesCluster < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    return unless (Rails.env.test? || Rails.env.development?) && !GitHub.enterprise? # rubocop:disable GitHub/DoNotBranchOnRailsEnv

    drop_table :page_builds, if_exists: true
    drop_table :page_certificates, if_exists: true
    drop_table :page_deployments, if_exists: true
    drop_table :page_updates, if_exists: true
    drop_table :pages, if_exists: true
    drop_table :pages_fileservers, if_exists: true
    drop_table :pages_migrations, if_exists: true
    drop_table :pages_partitions, if_exists: true
    drop_table :pages_protected_domains, if_exists: true
    drop_table :pages_replicas, if_exists: true
    drop_table :pages_routes, if_exists: true
  end
end
