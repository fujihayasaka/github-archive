# typed: true

# rubocop:disable GitHub/ExistingIdColumnsMustBeBigint
# The linter is disabled since the primary key of soa_dates is in int type

class SoaSsMakeAlertValidityNonNilable < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::SecurityOverviewAnalytics)

  def change
    change_column_null :soa_secret_scanning_alert_revisions, :alert_validity, false, 0
  end
end
