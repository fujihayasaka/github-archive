# typed: true
class SetDiscussionCategoryIdNotNull < ActiveRecord::Migration[7.1]
  use_connection_class(ApplicationRecord::Domain::Discussions)

  def up
    connection.execute(<<~SQL)
      ALTER TABLE discussions
      MODIFY `discussion_category_id` bigint(20) unsigned NOT NULL;
    SQL
  end

  def down
    connection.execute(<<~SQL)
      ALTER TABLE discussions
      MODIFY `discussion_category_id` bigint(20) unsigned DEFAULT NULL;
    SQL
  end
end
