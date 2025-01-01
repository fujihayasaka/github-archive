class AddBusinessReportExportsSettings < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    change_table(:business_report_exports, bulk: true) do |t|
      # Add nullable json column for report settings
      t.column :settings, :json, null: true
    end
  end
end
