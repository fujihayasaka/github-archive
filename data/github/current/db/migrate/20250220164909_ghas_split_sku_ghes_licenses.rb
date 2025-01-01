# typed: true
# frozen_string_literal: true

class GhasSplitSKUGhesLicenses < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::LicensingCollab)

  def change
    change_table :ghes_licenses, bulk: true do |t|
      t.column :code_security_enabled, :boolean, null: false, default: false
      t.column :code_security_licenses, :integer, null: false, default: 0
      t.column :secret_protection_enabled, :boolean, null: false, default: false
      t.column :secret_protection_licenses, :integer, null: false, default: 0
    end
  end
end
