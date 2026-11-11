class UpdatePublicKeyColumnsToUtf8mb4 < ActiveRecord::Migration[7.2]
  use_connection_class ApplicationRecord::Domain::Users

  def up
    connection.execute(<<~SQL)
      ALTER TABLE public_keys
        MODIFY COLUMN `title` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci DEFAULT NULL
    SQL
  end

  def down
    connection.execute(<<~SQL)
      ALTER TABLE public_keys
        MODIFY COLUMN `title` varchar(255) DEFAULT NULL
    SQL
  end
end
