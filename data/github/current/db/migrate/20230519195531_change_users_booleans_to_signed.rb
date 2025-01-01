# typed: true

class ChangeUsersBooleansToSigned < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def up
    return if !GitHub.enterprise? && !Rails.env.development?

    columns = {
      "wants_email": "tinyint(1) DEFAULT '1'",
      "disabled": "tinyint(1) DEFAULT '0'",
      "spammy": "tinyint(1) DEFAULT '0'",
      "gift": "tinyint(1) DEFAULT NULL"
    }

    columns_to_alter = columns.keys.select { |name| User.columns_hash[name.to_s].sql_type == "tinyint unsigned" }
    return if columns_to_alter.empty?

    sql = "ALTER TABLE users #{columns_to_alter.map { |name| "MODIFY COLUMN #{name} #{columns[name]}" }.join(", ")}"
    connection.execute(sql)
  end

  def down
  end
end
