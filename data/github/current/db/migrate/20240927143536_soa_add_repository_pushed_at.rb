# typed: true

class SoaAddRepositoryPushedAt < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::SecurityOverviewAnalytics)

  def change
    change_table :soa_repositories, bulk: true do |t|
      t.datetime :pushed_at, null: true, precision: 6
    end
  end
end
