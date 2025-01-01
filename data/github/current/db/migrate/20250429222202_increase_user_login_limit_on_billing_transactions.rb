# typed: true
# frozen_string_literal: true

class IncreaseUserLoginLimitOnBillingTransactions < ActiveRecord::Migration[8.1]
  # Increase the limit of the user_login column in the billing_transactions table from varchar(40) to varchar(60)
  # This migration is necessary to accommodate the association of Business records to billing transactions where the Business's slug is used as the user_login.
  # The Business slug is a string that can be up to 60 characters, hence the need to increase the limit.
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def up
    change_column :billing_transactions, :user_login, :string, limit: 60
  end

  def down
    msg = "Cannot reduce the user_login column limit back to 40 characters from 60 as it may result in data loss."
    raise ActiveRecord::IrreversibleMigration, msg
  end
end
