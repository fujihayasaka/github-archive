# typed: true
class AddPageCertificateTimestamps < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    change_table :page_certificates, bulk: true do |t|
      t.change :id, :bigint, unsigned: true, null: false, auto_increment: true
      t.datetime :updated_at, precision: 6
    end
  end
end
