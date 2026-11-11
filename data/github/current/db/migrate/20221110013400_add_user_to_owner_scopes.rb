# typed: true

class AddUserToOwnerScopes < ActiveRecord::Migration[7.0]
  self.use_connection_class(ApplicationRecord::TokenScanningService)
  def change
    change_table(:owner_scopes, bulk: :true) do |t|
      t.change :owner_scope, "ENUM('REPO', 'ORG', 'BIZ', 'USER')", null: false, comment: "scope for owner_id"
    end
  end
end
