# typed: true
# rubocop:disable GitHub/ExistingIdColumnsMustBeBigint

class AddRequire2faByToUsers < ActiveRecord::Migration[7.1]
  def change
    change_table :users, bulk: true do |t|
      t.datetime :require_2fa_by, precision: nil, default: nil, null: true
      t.index [:require_2fa_by], name: "index_users_on_require_2fa_by", unique: false
    end
  end
end
