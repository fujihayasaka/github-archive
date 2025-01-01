# typed: true

class DropTwoFactorRequirementStateFromUsers < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    change_table :users, bulk: true do |t|
      t.remove_index name: "index_users_on_two_factor_requirement_state"
      t.remove :two_factor_requirement_state
    end
  end
end
