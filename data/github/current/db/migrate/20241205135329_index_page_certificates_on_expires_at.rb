# typed: true

class IndexPageCertificatesOnExpiresAt < ActiveRecord::Migration[8.1]
  # rubocop:todo GitHub/EnsureDomainIsolationInMigration (can be dropped once table move completed)
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    change_table :page_certificates, bulk: true do |t|
      t.index [:expires_at], name: "index_page_certificates_on_expires_at"
    end
  end
end
