# typed: true
class DiscussionCategorySlugUpdateCharset < ActiveRecord::Migration[7.1]
  use_connection_class(ApplicationRecord::Domain::Discussions)

  def up
    connection.execute(<<~SQL)
      ALTER TABLE discussion_categories
      CONVERT TO
        CHARACTER SET utf8mb4
        COLLATE utf8mb4_unicode_520_ci
      SQL
  end

  def down
    connection.execute(<<~SQL)
      ALTER TABLE discussion_categories
      CONVERT TO
        CHARACTER SET utf8
        COLLATE utf8_general_ci
      SQL
  end
end
