# typed: true
# rubocop:disable GitHub/ExistingIdColumnsMustBeBigint

class ChangeUserEmailsBooleansToSigned < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def up
    return if !GitHub.enterprise? && !Rails.env.development?

    column = UserEmail.columns_hash["primary"]
    return unless column.sql_type == "tinyint unsigned" && column.unsigned?

    change_table :user_emails, bulk: true do |t|
      t.change :primary, "tinyint(1) DEFAULT NULL"
    end
  end

  def down
  end
end
