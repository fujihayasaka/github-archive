# typed: true
# frozen_string_literal: true

class ConvertBusinessUserAccountsCharsetToUseUtf8mb4 < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)

  def up
    connection.execute "ALTER TABLE `business_user_accounts` CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci;"
    connection.execute "ALTER TABLE `business_user_accounts` MODIFY `verified_emails` mediumtext;"
  end

  def down
    connection.execute "ALTER TABLE `business_user_accounts` CONVERT TO CHARACTER SET utf8mb3 COLLATE utf8_general_ci;"
    connection.execute "ALTER TABLE `business_user_accounts` MODIFY `verified_emails` text;"
  end
end
