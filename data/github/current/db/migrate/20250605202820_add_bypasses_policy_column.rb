# typed: true
# frozen_string_literal: true

class AddBypassesPolicyColumn < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    change_table :public_keys, bulk: true do |t|
      t.column :bypasses_policy, :boolean, default: false, null: true, comment: "Access allowed even if the deploy key policy is disabled"
    end
  end
end
