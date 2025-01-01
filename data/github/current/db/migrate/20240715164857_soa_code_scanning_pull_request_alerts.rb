# typed: true
# rubocop:disable GitHub/ReferencingColumnsMustBeBigint
# The linter is disabled since the primary key of soa_dates is in int type

class SoaCodeScanningPullRequestAlerts < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::SecurityOverviewAnalytics)

  def change
    create_table :soa_code_scanning_pull_request_alerts, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      # Foreign keys
      t.integer     :date_id,                                   null: false, unsigned: true
      t.bigint      :repository_id,                             null: false, unsigned: true
      t.bigint      :alert_number,                              null: false, unsigned: true
      t.bigint      :alert_id,                                  null: false, unsigned: true
      t.bigint      :pull_request_id,                           null: false, unsigned: true
      t.bigint      :analysis_id,                               null: false, unsigned: true

      # Metadata
      t.datetime    :alert_created_at,                          null: false, precision: 3, comment: "The create_at timestamp of the alert when it was firstly introduced by an analysis."
      t.datetime    :alert_updated_at,                          null: false, precision: 3, comment: "The latest updated_at timestamp of the alert when the pull request merged."
      t.boolean     :alert_resolved,                            null: false, comment: "The resolved state of the alert when the pull request merged."
      t.column      :alert_resolution,                          :tinyint, unsigned: true, null: true, comment: "The resolution of the alert when the pull request merged."
      t.string      :alert_severity,                            null: true, limit: 12
      t.string      :ref,                                       null: false, limit: 255
      t.string      :tool,                                      null: false, limit: 255
      t.string      :rule_sarif_identifier,                     null: false, limit: 255

      # DFA/Autofix fields
      t.boolean     :has_dfa,                                   null: true, comment: "True if the alert had corresponding developer friendly alert in pull request."
      t.boolean     :has_dfa_comments,                          null: true, comment: "True if there was any user made comment to the alert's DFA."
      t.boolean     :has_autofix,                               null: true, comment: "True if the alert had corresponding autofix suggestion in pull request."
      t.boolean     :autofix_accepted,                          null: true, comment: "True if the alert was resolved by accepting the autofix suggestion."

      # Row auditing fields
      t.timestamps

      t.index [:repository_id, :pull_request_id, :alert_number], name: "idx_soa_code_scanning_pr_alert", unique: true
      t.index [:repository_id, :date_id, :alert_number], name: "idx_soa_code_scanning_pr_alert_revision"
    end
  end
end
