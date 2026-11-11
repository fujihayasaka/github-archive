class ChangePackagesEncodingToUtf8mb4 < ActiveRecord::Migration[5.2]
  def up
    execute <<~SQL
      ALTER TABLE dg_packages CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
    SQL
  end

  def down
    execute <<~SQL
      ALTER TABLE dg_packages CONVERT TO CHARACTER SET utf8 COLLATE;
    SQL
  end
end
