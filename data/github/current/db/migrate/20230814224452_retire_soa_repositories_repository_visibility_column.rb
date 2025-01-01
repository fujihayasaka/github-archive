# typed: true

class RetireSoaRepositoriesRepositoryVisibilityColumn < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::SecurityOverviewAnalytics)

  def change
    change_table :soa_repositories, bulk: true do |t|
      t.remove :repository_visibility
      t.remove_index name: "index_soa_repositories_on_org_archived_repo_visibility_name"

      t.change :visibility, :tinyint, unsigned: true, null: false
      t.index [:organization_id, :archived, :visibility, :name], name: "index_soa_repositories_on_org_archived_visibility_name"
    end
  end
end
