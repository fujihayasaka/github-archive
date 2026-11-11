class DependencySpecIdToBigInt < ActiveRecord::Migration[5.0]
  def up
    execute "ALTER TABLE dependency_specifications MODIFY COLUMN id bigint(20) NOT NULL AUTO_INCREMENT;"
  end

  def down
    execute "ALTER TABLE dependency_specifications MODIFY COLUMN id int(11) NOT NULL AUTO_INCREMENT;"
  end
end
