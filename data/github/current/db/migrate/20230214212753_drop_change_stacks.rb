# typed: true

class DropChangeStacks < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Ballast)

  def change
    drop_table :change_stacks, if_exists: true
  end
end
