# typed: true
# frozen_string_literal: true

class AddBillingTradeScreeningStatusToUserPersonalProfiles < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)

  def change
    change_table :user_personal_profiles, bulk: true do |t|
      t.column :billing_trade_screening_status, :tinyint, null: false, default: 0
    end
  end
end
