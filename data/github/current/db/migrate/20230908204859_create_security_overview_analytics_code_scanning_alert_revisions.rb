# typed: true

# rubocop:disable GitHub/ReferencingColumnsMustBeBigint
# The linter is disabled since the primary key of soa_dates is in int type

class CreateSecurityOverviewAnalyticsCodeScanningAlertRevisions < ActiveRecord::Migration[7.1]
  use_connection_class(ApplicationRecord::SecurityOverviewAnalytics)

  def change
    create_table :soa_code_scanning_alert_revisions, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      # Foreign keys
      t.integer     :date_id,                                   null: false, unsigned: true
      t.integer     :next_revision_date_id,                     null: false, unsigned: true
      t.bigint      :repository_id,                             null: false, unsigned: true

      t.bigint      :alert_number,                              null: false, unsigned: true

      # Alert filterable fields
      t.boolean     :alert_resolved,                            null: false
      t.column      :alert_resolution,                          :tinyint, unsigned: true, null: true
      t.string      :alert_severity,                            null: true, limit: 12
      t.string      :tool,                                      null: false, limit: 255
      t.string      :language,                                  null: false, limit: 255
      t.string      :ref,                                       null: false, limit: 255

      # Alert auditing fields
      t.datetime    :alert_created_at,                          null: false, precision: 3
      t.datetime    :alert_updated_at,                          null: false, precision: 3
      t.datetime    :alert_resolved_at,                         null: true, precision: 3

      # Analytics auditing fields
      t.timestamps

      t.index [:repository_id, :date_id, :alert_number], name: "index_soa_code_scanning_alert_revs_on_repo_date_alert", unique: true
      t.index [:repository_id, :next_revision_date_id, :date_id], name: "index_soa_code_scanning_alert_revs_on_repo_dates"
    end
  end
end
