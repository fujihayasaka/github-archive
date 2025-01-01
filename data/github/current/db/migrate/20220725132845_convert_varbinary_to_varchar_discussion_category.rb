# typed: true

class ConvertVarbinaryToVarcharDiscussionCategory < ActiveRecord::Migration[7.1]
  use_connection_class ApplicationRecord::Collab

  def up
    connection.execute(<<~SQL)
      ALTER TABLE discussion_categories
      MODIFY `emoji` VARCHAR(44) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci NOT NULL DEFAULT ':hash:' ;
    SQL
  end

  def down
    connection.execute(<<~SQL)
      ALTER TABLE discussion_categories
      MODIFY `emoji` VARBINARY(44) NOT NULL DEFAULT ':hash:';
    SQL
  end
end
