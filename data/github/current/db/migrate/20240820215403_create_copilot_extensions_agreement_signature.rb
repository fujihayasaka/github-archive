class CreateCopilotExtensionsAgreementSignature < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    create_table :copilot_extensions_agreement_signatures, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :signatory_id, null: false, index: true, unsigned: true, comment: "The user who signed the agreement"
      t.bigint :organization_id, index: true, unsigned: true, comment: "Optional. The organization that the user signed the agreement on behalf of"
      t.bigint :business_id, index: true, unsigned: true, comment: "Optional. The business that the user signed the agreement on behalf of"

      t.timestamps
    end
  end
end
