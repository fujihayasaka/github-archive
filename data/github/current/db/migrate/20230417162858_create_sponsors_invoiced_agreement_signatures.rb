# typed: true
class CreateSponsorsInvoicedAgreementSignatures < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Sponsors)

  def change
    create_table(:sponsors_invoiced_agreement_signatures,
      id: :bigint,
      unsigned: true,
      charset: "utf8mb4",
      collation: "utf8mb4_unicode_520_ci",
    ) do |t|
      t.belongs_to :sponsors_agreement, null: false, index: false, unsigned: true
      t.belongs_to :signatory, null: false, index: false, unsigned: true
      t.belongs_to :organization, null: false, index: false, unsigned: true
      t.date :expires_on, null: false
      t.timestamps null: false

      t.index [:sponsors_agreement_id, :organization_id],
        name: "idx_sponsors_invoiced_agreement_signatures_on_spon_agree_org_id"
    end
  end
end
