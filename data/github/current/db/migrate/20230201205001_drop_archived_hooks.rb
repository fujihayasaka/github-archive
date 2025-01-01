# typed: true
# frozen_string_literal: true

class DropArchivedHooks < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Mysql1)

  def change
    drop_table :archived_hooks, if_exists: true
  end
end
