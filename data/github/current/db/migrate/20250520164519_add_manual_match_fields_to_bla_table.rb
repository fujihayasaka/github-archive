# typed: true
# frozen_string_literal: true

class AddManualMatchFieldsToBlaTable < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Billing)

  def change
    change_table :bundled_license_assignments, bulk: true do |t|
      t.string :identity, limit: 320, null: false, default: ""
      t.boolean :manual_match, null: false, default: false
      t.datetime :manual_match_at, precision: 6, null: true

      t.index [:business_id, :identity], name: "index_bundled_license_assignments_on_business_id_and_identity"
      t.index :identity, name: "index_bundled_license_assignments_on_identity"
    end
  end
end
