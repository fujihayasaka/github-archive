# typed: true
# frozen_string_literal: true

class RepositoriesPushesSha256RefPushes < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::RepositoriesPushes)

  def up
    change_table :ref_pushes, bulk: true do |t|
      t.change :after, :string, limit: 64, null: false
    end
  end

  def down
    change_table :ref_pushes, bulk: true do |t|
      t.change :after, :string, limit: 40, null: false
    end
  end
end
