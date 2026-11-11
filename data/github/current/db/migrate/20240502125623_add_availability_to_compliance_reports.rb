class AddAvailabilityToComplianceReports < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)

  def change
    add_column :compliance_reports, :availability, :tinyint, null: false, default: 0, after: :title
  end
end
