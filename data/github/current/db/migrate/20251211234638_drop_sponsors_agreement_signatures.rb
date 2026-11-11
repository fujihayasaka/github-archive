# typed: true

class DropSponsorsAgreementSignatures < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Sponsors)

  def up
    drop_table :sponsors_agreement_signatures
  end

  def down
    create_table :sponsors_agreement_signatures, id: :bigint, unsigned: true, charset: "utf8mb3" do |t| # rubocop:disable GitHub/NoNewTablesOnSharedDbClusters
      t.bigint :sponsors_agreement_id, null: false, unsigned: true
      t.bigint :sponsors_listing_id, null: false, unsigned: true
      t.bigint :signatory_id, null: false, unsigned: true
      t.timestamps null: false

      t.index [:sponsors_agreement_id, :sponsors_listing_id, :signatory_id], unique: true,
        name: "idx_sponsors_agreement_signatures_on_agreement_listing_signatory"
      t.index :sponsors_listing_id, name: "index_sponsors_agreement_signatures_on_sponsors_listing_id"
      t.index :signatory_id, name: "index_sponsors_agreement_signatures_on_signatory_id"
    end
  end
end
