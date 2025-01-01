class AddNotesToSponsorsInvoicedAgreementSignatures < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Sponsors)

  def change
    change_table :sponsors_invoiced_agreement_signatures, bulk: true do |t|
      t.column :notes, :text, null: true
    end
  end
end
