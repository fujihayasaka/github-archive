# typed: true

class SoaAddFeatureStatusTable < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::SecurityOverviewAnalytics)

  def change
    create_table :soa_feature_statuses, id: false, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      # Because this table is 1:1 with repositories, we can use that as the PK rather than introducing our own surrogate.
      # This gives us benefits like not needing a roundtrip to generate ids, and the PK is automatically included as  trailing key in all indexes.
      t.bigint    :repository_id, null: false, unsigned: true, primary_key: true, auto_increment: false

      # advanced security
      t.column    :advanced_security_status,                "enum('ENABLED', 'NOT_ENABLED')", null: false, default: "NOT_ENABLED"

      # dependabot state + alert count by severity
      t.column    :dependabot_alerts_status,                "enum('ENABLED', 'NOT_ENABLED')", null: false, default: "NOT_ENABLED"
      t.bigint    :dependabot_alerts_total_count,           null: false, unsigned: true, default: 0
      t.bigint    :dependabot_alerts_critical_count,        null: false, unsigned: true, default: 0
      t.bigint    :dependabot_alerts_high_count,            null: false, unsigned: true, default: 0
      t.bigint    :dependabot_alerts_medium_count,          null: false, unsigned: true, default: 0
      t.bigint    :dependabot_alerts_low_count,             null: false, unsigned: true, default: 0

      # code scanning state + alert count by severity
      t.column    :code_scanning_alerts_status,             "enum('ENABLED', 'NOT_ENABLED')", null: false, default: "NOT_ENABLED"
      t.bigint    :code_scanning_alerts_total_count,        null: false, unsigned: true, default: 0
      t.bigint    :code_scanning_alerts_critical_count,     null: false, unsigned: true, default: 0
      t.bigint    :code_scanning_alerts_high_count,         null: false, unsigned: true, default: 0
      t.bigint    :code_scanning_alerts_medium_count,       null: false, unsigned: true, default: 0
      t.bigint    :code_scanning_alerts_low_count,          null: false, unsigned: true, default: 0
      t.bigint    :code_scanning_alerts_info_count,         null: false, unsigned: true, default: 0

      # secret scanning state + alert count
      t.column    :secret_scanning_alerts_status,           "enum('ENABLED', 'NOT_ENABLED')", null: false, default: "NOT_ENABLED"
      t.bigint    :secret_scanning_alerts_total_count,      null: false, unsigned: true, default: 0

      # supplementary feature states
      t.column    :dependabot_security_updates_status,      "enum('ENABLED', 'NOT_ENABLED')", null: false, default: "NOT_ENABLED"
      t.column    :dependabot_version_updates_status,       "enum('ENABLED', 'NOT_ENABLED')", null: false, default: "NOT_ENABLED"
      t.column    :code_scanning_auto_codeql_status,        "enum('ENABLED', 'ELIGIBLE', 'NOT_ELIGIBLE')", null: false, default: "NOT_ELIGIBLE"
      t.column    :code_scanning_pr_reviews_status,         "enum('ENABLED', 'NOT_ENABLED')", null: false, default: "NOT_ENABLED"
      t.column    :secret_scanning_push_protection_status,  "enum('ENABLED', 'NOT_ENABLED')", null: false, default: "NOT_ENABLED"

      t.timestamps
    end
  end
end
