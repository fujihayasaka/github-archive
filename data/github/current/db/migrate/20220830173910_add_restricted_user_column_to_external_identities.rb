# typed: false
class AddRestrictedUserColumnToExternalIdentities < ActiveRecord::Migration[7.1]
  change_table(:external_identities, bulk: true) do |t|
    t.boolean :restricted_user, null: false, default: false
  end
end
