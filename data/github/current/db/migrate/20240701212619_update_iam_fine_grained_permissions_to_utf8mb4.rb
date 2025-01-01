class UpdateIamFineGrainedPermissionsToUtf8mb4 < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Iam)
  def up
    connection.execute(<<~SQL)
      ALTER TABLE fine_grained_permissions
      CONVERT TO
        CHARACTER SET utf8mb4
        COLLATE utf8mb4_unicode_520_ci
    SQL
  end

  def down
    connection.execute(<<~SQL)
      ALTER TABLE fine_grained_permissions
      CONVERT TO
        CHARACTER SET utf8mb3
        COLLATE utf8mb3_general_ci
    SQL
  end
end
