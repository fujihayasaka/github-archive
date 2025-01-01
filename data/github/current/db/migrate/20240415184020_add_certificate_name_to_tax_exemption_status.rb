class AddCertificateNameToTaxExemptionStatus < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Billing)

  def change
    add_column :tax_exemption_statuses, :certificate_name, "varchar(48)"
  end
end
