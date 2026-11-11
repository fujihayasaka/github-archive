# frozen_string_literal: true

class AddIndexToReposPrivate < ActiveRecord::Migration[6.0]
  def change
    add_index :repos, :private
  end
end
