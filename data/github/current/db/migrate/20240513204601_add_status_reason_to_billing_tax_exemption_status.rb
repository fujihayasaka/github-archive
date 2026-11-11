class AddStatusReasonToBillingTaxExemptionStatus < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Billing)

  def change
    add_column :tax_exemption_statuses, :status_reason, :string, limit: 255
  end
end
