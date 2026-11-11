# typed: true
# frozen_string_literal: true

class AddPartnerSupportOfferingToSalesforceAccounts < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    add_column :salesforce_accounts, :partner_support_offering, :string, limit: 40
  end
end
