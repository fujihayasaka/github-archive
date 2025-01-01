# typed: true
# rubocop:disable GitHub/ExistingIdColumnsMustBeBigint

class AddTwoFactorRequirementState < ActiveRecord::Migration[7.1]
  def change
    change_table :users, bulk: true do |t|

      t.column :two_factor_requirement_state, "tinyint(4)", null: false, default: 0
      t.index [:two_factor_requirement_state], name: "index_users_on_two_factor_requirement_state", unique: false
    end
  end
end
