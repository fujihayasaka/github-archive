# typed: true
class ChangeGistsBooleansToSigned < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Gists)

  def up
    return if !GitHub.enterprise? && !Rails.env.development?

    columns = {
      "delete_flag": "tinyint(1) NOT NULL DEFAULT '0'",
      "public": "tinyint(1) DEFAULT '0'"
    }

    columns_to_alter = columns.keys.select { |name| Gist.columns_hash[name.to_s].sql_type == "tinyint unsigned" }
    return if columns_to_alter.empty?

    sql = "ALTER TABLE gists #{columns_to_alter.map { |name| "MODIFY COLUMN #{name} #{columns[name]}" }.join(", ")}"
    connection.execute(sql)
  end

  def down
  end
end
