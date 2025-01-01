# typed: true
# frozen_string_literal: true

class SoaRepositoryOwnerRepositoriesIndex < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::SecurityOverviewAnalytics)

  def change
    change_table :soa_repositories, bulk: true do |t|
      t.index [:owner_id, :owner_type, :repository_id], name: "index_soa_repositories_on_owner_repo"
    end
  end
end
