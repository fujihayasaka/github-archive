class CreateScopedVulnerabilities < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Vulnerabilities)

  def change
    create_table :scoped_vulnerabilities, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.string :status, null: false, limit: 12
      t.string :severity, limit: 12
      t.string :classification, limit: 255
      t.mediumblob :description
      t.datetime :published_at, precision: nil
      t.datetime :withdrawn_at, precision: nil
      t.boolean :simulation, null: false, default: false
      t.string :ghsa_id, null: false, limit: 19
      t.string :cve_id, limit: 20
      t.string :white_source_id, limit: 20
      t.binary :summary, limit: 1024
      t.unsigned_bigint :npm_id
      t.binary :cvss_v3, limit: 255
      t.binary :source_code_location, limit: 1024
      t.datetime :reviewed_at, precision: 6
      t.datetime :nvd_published_at, precision: 6
      t.string :scope, limit: 20
      t.bigint :security_advisory_id, unsigned: true, null: false, default: 0
      t.bigint :advisory_repository_id, unsigned: true, null: false, default: 0
      t.timestamps precision: nil

      t.index :ghsa_id, unique: true
      t.index :published_at
      t.index :updated_at
      t.index :cve_id
      t.index :security_advisory_id
      t.index [:scope, :advisory_repository_id]
      t.index [:status, :simulation, :updated_at], name: "index_scoped_vulns_on_status_and_simulation_and_updated_at"
    end
  end
end
