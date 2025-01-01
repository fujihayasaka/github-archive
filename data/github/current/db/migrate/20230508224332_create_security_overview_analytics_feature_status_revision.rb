# typed: true
# rubocop:disable GitHub/ReferencingColumnsMustBeBigint
# The linter is disabled since the primary key of soa_dates is in int type
class CreateSecurityOverviewAnalyticsFeatureStatusRevision < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::SecurityOverviewAnalytics)

  def change
    create_table :soa_feature_status_revisions, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|

      t.integer     :date_id,                                   null: false, unsigned: true
      t.integer     :next_revision_date_id,                     null: false, unsigned: true
      t.bigint      :repository_id,                             null: false, unsigned: true

      t.boolean     :dependabot_alerts_enabled,                 null: false
      t.boolean     :advanced_security_enabled,                 null: false
      t.boolean     :code_scanning_enabled,                     null: false
      t.boolean     :secret_scanning_enabled,                   null: false
      t.boolean     :secret_scanning_push_protection_enabled,   null: false

      t.timestamps

      t.index [:repository_id, :next_revision_date_id, :date_id], name: "index_soa_feature_statuses_on_repo_dates"
    end
  end
end
