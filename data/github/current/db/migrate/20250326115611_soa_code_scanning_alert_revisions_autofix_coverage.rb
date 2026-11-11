# typed: true

# rubocop:disable GitHub/ExistingIdColumnsMustBeBigint
# The linter is disabled since the primary key of soa_dates is an int type

class SoaCodeScanningAlertRevisionsAutofixCoverage < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::SecurityOverviewAnalytics)

  def up
    change_table :soa_code_scanning_alert_revisions, bulk: true do |t|
      t.remove_index name: "index_soa_slice4_cs_alert_revs_on_dashboard_dates_coverage"
      t.remove_index name: "index_soa_code_scanning_alert_revs_on_dashboard_dates_coverage"
      # Update covering index to include has_autofix and autofix_accepted columns to allow faster filtering.
      t.index [:slice4, :repository_id, :alert_resolved, :alert_resolution, :tool, :alert_severity, :date_id, :next_revision_date_id,  :alert_created_at, :alert_resolved_at, :alert_reopened_at, :rule_sarif_identifier, :has_autofix, :autofix_accepted], name:  "index_soa_slice4_cs_alert_revs_on_dashboard_dates_coverage"
      t.index          [:repository_id, :alert_resolved, :alert_resolution, :tool, :alert_severity, :date_id, :next_revision_date_id,  :alert_created_at, :alert_resolved_at, :alert_reopened_at, :rule_sarif_identifier, :has_autofix, :autofix_accepted], name:  "index_soa_code_scanning_alert_revs_on_dashboard_dates_coverage"
    end
  end

  def down
    change_table :soa_code_scanning_alert_revisions, bulk: true do |t|
      t.remove_index name: "index_soa_slice4_cs_alert_revs_on_dashboard_dates_coverage"
      t.remove_index name: "index_soa_code_scanning_alert_revs_on_dashboard_dates_coverage"
      t.index [:slice4, :repository_id, :alert_resolved, :alert_resolution, :tool, :alert_severity, :date_id, :next_revision_date_id,  :alert_created_at, :alert_resolved_at, :alert_reopened_at, :rule_sarif_identifier], name:  "index_soa_slice4_cs_alert_revs_on_dashboard_dates_coverage"
      t.index          [:repository_id, :alert_resolved, :alert_resolution, :tool, :alert_severity, :date_id, :next_revision_date_id,  :alert_created_at, :alert_resolved_at, :alert_reopened_at, :rule_sarif_identifier], name:  "index_soa_code_scanning_alert_revs_on_dashboard_dates_coverage"
    end
  end
end
