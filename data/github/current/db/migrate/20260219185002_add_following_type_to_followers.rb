# typed: true
# frozen_string_literal: true

class AddFollowingTypeToFollowers < ActiveRecord::Migration[8.2]
  use_connection_class(ApplicationRecord::Domain::Users)

  def up
    change_table :followers, bulk: true do |t|
      t.string :following_type, limit: 30, null: true

      t.index [:user_id, :following_type, :user_hidden, :created_at],
        order: { created_at: :desc },
        name: "index_followers_on_user_id_flw_type_user_hidden_created_at"
      t.index [:user_id, :user_hidden, :following_type],
        name: "index_followers_on_user_id_user_hidden_flw_type"

      # Dead index reported by `.mysql dead-indexes followers mysql1`
      t.remove_index name: "index_followers_on_created_at_and_following_id"
    end
  end

  def down
    change_table :followers, bulk: true do |t|
      t.remove_index name: "index_followers_on_user_id_flw_type_user_hidden_created_at"
      t.remove_index name: "index_followers_on_user_id_user_hidden_flw_type"
      t.remove :following_type

      t.index [:created_at, :following_id],
        name: "index_followers_on_created_at_and_following_id"
    end
  end
end
