# typed: true
class ChangeLanguagesBooleansToSigned < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Repositories)

  def up
    return if !GitHub.enterprise? && !Rails.env.development?

    column = Language.columns_hash["public"]
    return unless column.sql_type == "tinyint unsigned" && column.unsigned?

    change_table :languages, bulk: true do |t|
      t.change :public, "tinyint(1) DEFAULT '1'"
    end
  end

  def down
  end
end
