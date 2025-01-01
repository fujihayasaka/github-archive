class ChangeHolderToString < ActiveRecord::Migration[6.0]
  # See ../../go/mysql-lock/main.go.
  def up
    change_column :dg_locks, :holder, "string"
  end

  def down
    change_column :dg_locks, :holder, "varchar(64)"
  end
end
