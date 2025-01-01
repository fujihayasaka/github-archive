# typed: true

class AddDiscussionCategoryPins < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Discussions)

  def change
    create_table :discussion_category_pins, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :repository_id, null: false, unsigned: true, comment: "the repository which the discussion belongs to"
      t.bigint :discussion_id, null: false, unsigned: true, comment: "the discussion which is pinned"
      t.bigint :pinned_by_id, null: false, unsigned: true, comment: "the user which pinned the discussion"
      t.bigint :category_id, null: false, unsigned: true, comment: "the category which the discussion is pinned in"

      t.timestamps
    end

    # we'll be querying by repository_id and category_id. A discussion can only be pinned in a single category, and only once in tht category
    add_index :discussion_category_pins, [:repository_id, :category_id, :discussion_id], unique: true, name: "index_unique_discussion_category_pin"
    # for now pins won't have a position column and we'll just order by created_at.  Given the low number of total pins/category, though
    # we might be able to avoid this index
    add_index :discussion_category_pins, :created_at

    # When we're showing an individual discussion, we'll need to know if it's pinned in a given category
    # we can't use the compound index above because `discussion_id` is the last column
    # https://dev.mysql.com/doc/refman/8.0/en/multiple-column-indexes.html
    add_index :discussion_category_pins, :discussion_id
  end
end
