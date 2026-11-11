# typed: true
# frozen_string_literal: true

class DropGistUserSubscriptions < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Gists)

  def change
    drop_table :gist_user_subscriptions, if_exists: true
  end
end
