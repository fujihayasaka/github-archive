# typed: true
class ChangeProfilesBooleansToSigned < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def up
    return if !GitHub.enterprise? && !Rails.env.development?

    column = Profile.columns_hash["hireable"]
    return unless column.sql_type == "tinyint unsigned" && column.unsigned?

    change_table :profiles, bulk: true do |t|
      t.change :hireable, "tinyint(1) DEFAULT '0'"
    end
  end

  def down
  end
end
