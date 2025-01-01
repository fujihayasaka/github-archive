class ConvertBusinessesCharSetToUseUtf8mb4 < ActiveRecord::Migration[7.1]
  def up
    connection.execute "ALTER TABLE `businesses` CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci;"
    connection.execute "ALTER TABLE `businesses` MODIFY `name` varchar(240) NOT NULL;"
    connection.execute "ALTER TABLE `businesses` MODIFY `terms_of_service_company_name` varchar(240) DEFAULT NULL;"
    connection.execute "ALTER TABLE `businesses` MODIFY `description` varchar(640) DEFAULT NULL;"
    connection.execute "ALTER TABLE `businesses` MODIFY `spammy_reason` mediumtext;"
  end

  def down
    connection.execute "ALTER TABLE `businesses` CONVERT TO CHARACTER SET utf8mb3 COLLATE utf8_general_ci;"
    connection.execute "ALTER TABLE `businesses` MODIFY `name` varbinary(240) NOT NULL;"
    connection.execute "ALTER TABLE `businesses` MODIFY `terms_of_service_company_name` varbinary(240) DEFAULT NULL;"
    connection.execute "ALTER TABLE `businesses` MODIFY `description` varbinary(640) DEFAULT NULL;"
    connection.execute "ALTER TABLE `businesses` MODIFY `spammy_reason` text;"
  end
end
