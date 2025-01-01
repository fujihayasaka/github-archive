# typed: true
class AddVisibilityColumnToSoaRepositoriesToReplaceRepositoryVisibility < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::SecurityOverviewAnalytics)

  def change
    change_table :soa_repositories, bulk: true do |t|
      t.change    :repository_visibility, :tinyint, unsigned: true, null: true
      t.column    :visibility, :tinyint, unsigned: true, null: true
    end
  end
end
