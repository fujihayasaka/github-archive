# typed: true
class AddErrorAndStatusToBusinessReportExports < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Mysql1)

  def up
    change_table :business_report_exports, bulk: true do |t|
      t.datetime :errored_at, precision: 6, null: true,
        comment: "timestamp of when the export errored_out (if it did)"
      t.column   :status, :string, limit: 36, null: true,
        comment: "the progress of the export in x/y user format"

      t.index [:owner_id, :owner_type, :report_type, :errored_at],
        name: "idx_business_report_exports_owner_report_type_errored_at"
      t.index [:owner_id, :owner_type, :report_type, :status],
        name: "idx_business_report_exports_owner_report_type_status"
    end
  end

  def down
    change_table :business_report_exports do |t|
      t.remove :status
      t.remove :errored_at

      t.remove_index name: "idx_business_report_exports_owner_report_type_errored_at"
      t.remove_index name: "idx_business_report_exports_owner_report_type_status"
    end
  end
end
