class CreateOrganizationTermsOfServiceUpgradePrompts < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Users)
  def change
    create_table :organization_terms_of_service_upgrade_prompts, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :organization_id, :bigint, unsigned: true, null: false
      t.column :upgraded_terms_type, "enum('Corporate', 'ESA+Education')", null: false
      t.timestamps

      t.index [:organization_id, :upgraded_terms_type], unique: true, name: "index_org_terms_of_service_upgrade_prompts_on_org_and_terms"
    end
  end
end
