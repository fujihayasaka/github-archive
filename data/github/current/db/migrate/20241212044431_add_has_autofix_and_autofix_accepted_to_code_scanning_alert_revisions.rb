# typed: true

# rubocop:disable GitHub/ExistingIdColumnsMustBeBigint
# The linter is disabled since the primary key of soa_dates is an int type

class AddHasAutofixAndAutofixAcceptedToCodeScanningAlertRevisions < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::SecurityOverviewAnalytics)

  def change
    change_table :soa_code_scanning_alert_revisions, bulk: true do |t|
      t.boolean :has_autofix, null: true, default: nil
      t.boolean :autofix_accepted, null: true, default: nil
    end
  end
end
