# typed: true
# frozen_string_literal: true

class AddIndexToUserPersonalProfiles < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)

  def change
    change_table :user_personal_profiles, bulk: true do |t|
      t.virtual :marketplace_app_owner, type: :tinyint, limit: 1, null: false,
                as: "COALESCE(JSON_UNQUOTE(JSON_EXTRACT(`metadata`, '$.marketplace_app_owner')) = 'true', FALSE)"

      # Remove the redundant index
      t.remove_index [:msft_trade_screening_status], name: "index_on_msft_trade_screening_status"

      # Add the composite index
      t.index [:msft_trade_screening_status, :marketplace_app_owner], name: "index_profiles_on_screening_status_and_marketplace_app_owner"
    end
  end
end
