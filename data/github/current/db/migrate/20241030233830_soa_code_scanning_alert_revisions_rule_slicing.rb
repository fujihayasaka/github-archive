# typed: true

# rubocop:disable GitHub/ExistingIdColumnsMustBeBigint
# The linter is disabled since the primary key of soa_dates is an int type

class SoaCodeScanningAlertRevisionsRuleSlicing < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::SecurityOverviewAnalytics)

  def change
    change_table :soa_code_scanning_alert_revisions, bulk: true do |t|
      t.virtual :rule_slice4, as: "mod(crc32(rule_sarif_identifier),4)", type: :tinyint, stored: false
      t.index [:rule_slice4, :repository_id, :next_revision_date_id, :alert_severity, :tool, :date_id, :rule_sarif_identifier], name:  "index_soa_rule_slice4_cs_alert_revs"
    end
  end
end
