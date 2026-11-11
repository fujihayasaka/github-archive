# typed: true
# frozen_string_literal: true

class AddPublishAtToDiscussions < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Discussions)

  def change
    change_table :discussions, bulk: true do |t|
      t.datetime :publish_at, after: :chosen_comment_id, precision: 0

      t.index [:state, :publish_at]
    end
  end
end
