# typed: true
# frozen_string_literal: true

class DropBillToFromCustomer < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    change_table :customers, bulk: true do |t|
      t.remove :bill_to, type: :string
      t.remove :billing_instructions, type: :text
    end
  end
end
