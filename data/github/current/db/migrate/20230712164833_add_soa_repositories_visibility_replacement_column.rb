# typed: true
class AddSoaRepositoriesVisibilityReplacementColumn < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::SecurityOverviewAnalytics)

  def change
    change_table :soa_repositories, bulk: true do |t|
      t.change    :visibility, :string, null: true, limit: 50
      t.column    :repository_visibility, :tinyint, unsigned: true, null: true
    end
  end
end
