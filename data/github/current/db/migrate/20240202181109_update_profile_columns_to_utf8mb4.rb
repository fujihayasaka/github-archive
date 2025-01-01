class UpdateProfileColumnsToUtf8mb4 < ActiveRecord::Migration[7.2]
  use_connection_class ApplicationRecord::Domain::Users

  def up
    connection.execute(<<~SQL)
      ALTER TABLE profiles
      CONVERT TO
        CHARACTER SET utf8mb4
        COLLATE utf8mb4_unicode_520_ci,
      MODIFY COLUMN `bio` varchar(1024) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci DEFAULT NULL;
      SQL
  end

  def down
    connection.execute(<<~SQL)
      ALTER TABLE profiles
      CONVERT TO
        CHARACTER SET utf8
        COLLATE utf8_general_ci,
      MODIFY COLUMN `bio` varbinary(1024) DEFAULT NULL;
      SQL
  end
end
