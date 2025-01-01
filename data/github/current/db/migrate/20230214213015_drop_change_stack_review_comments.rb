# typed: true

class DropChangeStackReviewComments < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Ballast)

  def change
    drop_table :change_stack_review_comments, if_exists: true
  end
end
