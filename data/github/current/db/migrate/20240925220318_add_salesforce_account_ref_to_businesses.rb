# typed: true
# frozen_string_literal: true

class AddSalesforceAccountRefToBusinesses < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    add_reference :businesses, :salesforce_account, unsigned: true
  end
end
