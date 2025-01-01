# typed: true
# rubocop:disable GitHub/ExistingIdColumnsMustBeBigint

class DropUserRequire2faBy < ActiveRecord::Migration[7.1]
  def change
    change_table :users, bulk: true do |t|
      t.remove_index name: "index_users_on_require_2fa_by"
      t.remove :require_2fa_by
    end
  end
end
