# typed: true
# frozen_string_literal: true

class RemoveCustomersTrialExpiredButNotBillableSince < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def up
    connection.execute "ALTER TABLE `customers` CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci;"
    remove_column :customers, :trial_expired_but_not_billable_since
  end

  def down
    add_column :customers, :trial_expired_but_not_billable_since, :datetime, precision: 6
    connection.execute "ALTER TABLE `customers` CONVERT TO CHARACTER SET utf8mb3;"
  end
end
