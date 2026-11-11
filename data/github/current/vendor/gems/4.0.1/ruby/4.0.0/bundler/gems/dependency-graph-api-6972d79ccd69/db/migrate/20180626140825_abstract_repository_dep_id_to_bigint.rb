class AbstractRepositoryDepIdToBigint < ActiveRecord::Migration[5.0]
  def up
    execute "ALTER TABLE abstract_repository_dependencies MODIFY COLUMN id bigint(20) NOT NULL AUTO_INCREMENT;"
  end

  def down
    execute "ALTER TABLE abstract_repository_dependencies MODIFY COLUMN id int(11) NOT NULL AUTO_INCREMENT;"
  end

end
