class CreateLocksTable < ActiveRecord::Migration[6.0]
  def change
    # See ../../go/mysql-lock/main.go
    create_table :dg_locks, id: false, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci" do |t|
      t.string :lockname, null: false, primary_key: true # `lockname` VARCHAR(64) PRIMARY KEY,
      t.string :holder, null: false                      # `holder` VARCHAR(64)
      t.datetime :expires, null: false                   # `expires` DATETIME
    end
  end
end
