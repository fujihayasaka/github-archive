class DropGitSizer < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Spokes)

  def change
    drop_table :git_sizer
  end
end
