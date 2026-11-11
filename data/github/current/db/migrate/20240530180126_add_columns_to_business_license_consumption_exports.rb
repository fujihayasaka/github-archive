class AddColumnsToBusinessLicenseConsumptionExports < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def up
    change_table :business_license_consumption_exports, bulk: true do |t|
      t.boolean :triggered_via_stafftools, null: false, default: false,
        comment: "true if the export was triggered through stafftools"
      t.datetime :completed_at, precision: 6, null: true,
        comment: "timestamp of when the export was completed"
      t.datetime :notified_at, precision: 6, null: true,
        comment: "timestamp of when the email notification was triggered"
    end
  end

  def down
    change_table :business_license_consumption_exports, bulk: true do |t|
      t.remove :triggered_via_stafftools
      t.remove :completed_at
      t.remove :notified_at
    end
  end
end
