# typed: true

class ChangeRepositoriesBooleansToSigned < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def up
    return if !GitHub.enterprise? && !Rails.env.development?

    columns = {
      "public": "tinyint(1) DEFAULT '1'",
      "public_push": "tinyint(1) DEFAULT NULL",
      "locked": "tinyint(1) DEFAULT '0'",
      "has_issues": "tinyint(1) DEFAULT '1'",
      "has_wiki": "tinyint(1) DEFAULT '1'",
      "has_downloads": "tinyint(1) DEFAULT '1'",
      "sandbox": "tinyint(1) DEFAULT NULL",
    }

    columns_to_alter = columns.keys.select { |name| Repository.columns_hash[name.to_s].sql_type == "tinyint unsigned" }
    return if columns_to_alter.empty?

    sql = "ALTER TABLE repositories #{columns_to_alter.map { |name| "MODIFY COLUMN #{name} #{columns[name]}" }.join(", ")}"
    connection.execute(sql)
  end

  def down
  end
end
