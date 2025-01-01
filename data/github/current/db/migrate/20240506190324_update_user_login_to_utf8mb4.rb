class UpdateUserLoginToUtf8mb4 < ActiveRecord::Migration[7.2]
  use_connection_class ApplicationRecord::Domain::Users

  def up
    connection.execute(<<~SQL)
      ALTER TABLE users
      MODIFY COLUMN `login` VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci NOT NULL;
    SQL
  end

  def down
    connection.execute(<<~SQL)
      ALTER TABLE users
      MODIFY COLUMN `login` VARCHAR(40) CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci NOT NULL;
    SQL
  end
end
