class ReleasesCharsetAndCollation < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Repositories)

  def up
    connection.execute(<<~SQL)
      ALTER TABLE releases
      CONVERT TO
        CHARACTER SET utf8mb4
        COLLATE utf8mb4_unicode_520_ci
    SQL

    connection.execute "ALTER TABLE `releases` MODIFY `body` mediumtext;"
  end

  def down
    connection.execute(<<~SQL)
      ALTER TABLE releases
      CONVERT TO
        CHARACTER SET utf8mb3
        COLLATE utf8_general_ci
    SQL

    connection.execute "ALTER TABLE `releases` MODIFY `body` mediumblob;"
  end
end
