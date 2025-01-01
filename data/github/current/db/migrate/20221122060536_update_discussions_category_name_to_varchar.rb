# typed: true
class UpdateDiscussionsCategoryNameToVarchar < ActiveRecord::Migration[7.1]
  use_connection_class(ApplicationRecord::Domain::Discussions)

  def up
    connection.execute(<<~SQL)
      ALTER TABLE discussion_categories
      MODIFY `name` VARCHAR(512) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci NOT NULL;
    SQL

    connection.execute(<<~SQL)
      ALTER TABLE archived_discussion_categories
      MODIFY `name` VARCHAR(512) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci NOT NULL;
    SQL
  end

  def down
    connection.execute(<<~SQL)
      ALTER TABLE discussion_categories
      MODIFY `name` VARBINARY(512) NOT NULL;
    SQL

    connection.execute(<<~SQL)
      ALTER TABLE archived_discussion_categories
      MODIFY `name` VARBINARY(512) NOT NULL;
    SQL
  end
end
