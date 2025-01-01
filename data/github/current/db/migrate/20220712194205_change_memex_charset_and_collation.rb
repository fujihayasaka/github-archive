# typed: true
class ChangeMemexCharsetAndCollation < ActiveRecord::Migration[7.1]
  use_connection_class ApplicationRecord::Memex

  def up
    connection.execute(<<~SQL)
      ALTER TABLE memex_projects
      CONVERT TO
        CHARACTER SET utf8mb4
        COLLATE utf8mb4_unicode_520_ci
      SQL
  end

  def down
    connection.execute(<<~SQL)
      ALTER TABLE memex_projects
      CONVERT TO
        CHARACTER SET utf8
        COLLATE utf8_general_ci
      SQL
  end
end
