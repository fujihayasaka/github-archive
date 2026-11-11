# typed: true
# frozen_string_literal: true

class AddCommentsEnabledToGists < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Gists)

  def change
    add_column :gists, :comments_enabled, :boolean, default: true, null: false
  end
end
