# typed: strict
# frozen_string_literal: true

class AddLastStatusAndTransactionIdIndexToBillingTransactions < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  sig { void }
  def up
    connection.execute "ALTER TABLE `billing_transactions` CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci;"
    add_index :billing_transactions, [:last_status, :transaction_id]
  end

  sig { void }
  def down
    remove_index :billing_transactions, [:last_status, :transaction_id]
    connection.execute "ALTER TABLE `billing_transactions` CONVERT TO CHARACTER SET utf8mb3;"
  end
end
