class UpdateUserStatusColumnsToUtf8mb4 < ActiveRecord::Migration[7.2]
  use_connection_class ApplicationRecord::Domain::Users

  def up
    connection.execute(<<~SQL)
      ALTER TABLE user_statuses
        MODIFY COLUMN `message` varchar(800) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci DEFAULT NULL;
    SQL
  end

  def down
    connection.execute(<<~SQL)
      ALTER TABLE user_statuses
        MODIFY COLUMN `message` varbinary(800) DEFAULT NULL;
    SQL
  end
end
