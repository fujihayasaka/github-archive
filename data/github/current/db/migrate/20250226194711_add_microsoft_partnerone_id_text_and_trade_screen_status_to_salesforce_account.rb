# typed: true
# frozen_string_literal: true

class AddMicrosoftPartneroneIdTextAndTradeScreenStatusToSalesforceAccount < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    change_table :salesforce_accounts, bulk: true do |t|
      t.text :microsoft_partnerone_id_text
      t.text :trade_screen_status
    end
  end
end
