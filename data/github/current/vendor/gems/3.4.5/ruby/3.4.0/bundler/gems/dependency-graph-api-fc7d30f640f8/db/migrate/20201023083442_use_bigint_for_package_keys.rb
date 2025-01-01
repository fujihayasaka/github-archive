class UseBigintForPackageKeys < ActiveRecord::Migration[6.0]
  def up
    change_column :dg_packages, :id, "bigint(11) unsigned NOT NULL AUTO_INCREMENT"
    change_column :dg_package_versions, :package_id, "bigint(11) unsigned NOT NULL"
    change_column :dg_abstract_package_dependencies, :dependent_id, "bigint(11) unsigned DEFAULT NULL"

    change_column :dg_package_versions, :id, "bigint(11) unsigned NOT NULL AUTO_INCREMENT"
    change_column :dg_dependency_specifications, :dependent_id, "bigint(11) unsigned NOT NULL"
  end

  def down
    change_column :dg_packages, :id, "int(11) NOT NULL AUTO_INCREMENT"
    change_column :dg_package_versions, :package_id, "int(11) NOT NULL"
    change_column :dg_abstract_package_dependencies, :dependent_id, "int(11) DEFAULT NULL"

    change_column :dg_package_versions, :id, "int(11) NOT NULL AUTO_INCREMENT"
    change_column :dg_dependency_specifications, :dependent_id, "int(11) NOT NULL"
  end
end
