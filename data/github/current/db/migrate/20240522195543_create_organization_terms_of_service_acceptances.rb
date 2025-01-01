class CreateOrganizationTermsOfServiceAcceptances < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Users)
  def change
    create_table :organization_terms_of_service_acceptances, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :organization_id, :bigint, unsigned: true, null: false
      t.column :accepted_terms_type, "enum('Custom', 'Corporate', 'Evaluation', 'ESA+Education', 'Standard')", null: false, default: "Standard"
      t.timestamps

      t.index :organization_id, unique: true, name: "index_org_terms_of_service_acceptances_on_org"
    end
  end
end
