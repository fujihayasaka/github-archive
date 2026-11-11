# typed: true

class CreateSecurityOverviewAnalyticsRepository < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::SecurityOverviewAnalytics)

  def change
    create_table :soa_repositories, id: false, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint        :repository_id,           null: false, unsigned: true, primary_key: true, auto_increment: false
      t.bigint        :organization_id,         null: false, unsigned: true
      t.string        :name,                    null: false, limit: 100
      t.string        :visibility,              null: false, limit: 50
      t.boolean       :archived,                null: false

      t.datetime      :event_time,              null: false, precision: 6
      t.timestamps

      t.index [:organization_id, :repository_id], unique: true, name: "index_soa_repositories_on_org_repo"
      t.index [:organization_id, :archived, :name], name: "index_soa_repositories_on_org_archived_name"
      t.index [:organization_id, :archived, :visibility, :name], name: "index_soa_repositories_on_org_archived_visibility_name"
    end
  end
end
