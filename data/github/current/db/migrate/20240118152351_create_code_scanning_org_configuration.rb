class CreateCodeScanningOrgConfiguration < ActiveRecord::Migration[7.2]
  use_connection_class(ApplicationRecord::Domain::RepositoriesNotify)

  def change
    create_table :code_scanning_org_configurations, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.references :organization, index: { unique: true }, null: false
      t.text :codeql_packs

      t.timestamps
    end
  end
end
