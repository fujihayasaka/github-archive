# typed: true

# rubocop:disable GitHub/ExistingIdColumnsMustBeBigint
# rubocop:disable GitHub/AvoidRedundantIndex

class RemoveUniquenessFromLoginIndexFromUsers < ActiveRecord::Migration[7.1]
  def up
    return unless GitHub.multi_tenant_enterprise?

    change_table :users, bulk: true do |t|
      t.remove_index name: "index_users_on_login"
      t.index [:login], name: "index_users_on_login", unique: false
    end
  end

  def down
    return unless GitHub.multi_tenant_enterprise?

    change_table :users, bulk: true do |t|
      t.remove_index name: "index_users_on_login"
      t.index [:login], name: "index_users_on_login", unique: true
    end
  end
end
