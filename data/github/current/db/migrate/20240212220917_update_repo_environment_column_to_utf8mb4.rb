class UpdateRepoEnvironmentColumnToUtf8mb4 < ActiveRecord::Migration[7.2]
  use_connection_class ApplicationRecord::Domain::Repositories

  def up
    connection.execute(<<~SQL)
      ALTER TABLE environments
        MODIFY COLUMN `name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci NOT NULL;
    SQL
  end

  def down
    connection.execute(<<~SQL)
      ALTER TABLE environments
        MODIFY COLUMN `name` varchar(255) NOT NULL;
    SQL
  end
end
