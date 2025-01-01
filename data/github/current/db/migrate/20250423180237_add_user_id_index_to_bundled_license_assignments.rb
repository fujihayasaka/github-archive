# typed: true
# frozen_string_literal: true

class AddUserIdIndexToBundledLicenseAssignments < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Billing)

  def change
    add_index :bundled_license_assignments, :user_id, name: "index_bundled_license_assignments_on_user_id"
  end
end
