# typed: true
# frozen_string_literal: true

# rubocop:disable GitHub/ExistingIdColumnsMustBeBigint
# The table references soa_dates.id, which is int type. We know the domain of the value; it is not auto increment.
# This is a storage optimization for projected growth.

class NullifyCodeScanningAlertRevisionLangAndRef < ActiveRecord::Migration[7.1]
  use_connection_class(ApplicationRecord::SecurityOverviewAnalytics)

  def change
    change_table :soa_code_scanning_alert_revisions, bulk: true do |t|
      t.change :language, "varchar(255)", null: true
      t.change :ref, "varbinary(1024)", null: true
    end
  end
end
