# typed: true
# frozen_string_literal: true

class ChangeEmailRolesBooleansToSigned < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Mysql1)

  def up
    change_table :email_roles, bulk: true do |t|
      t.change :id, "bigint(20) unsigned NOT NULL AUTO_INCREMENT"
      t.change :user_id, "bigint(20) unsigned NOT NULL"
      t.change :email_id, "bigint(20) unsigned NOT NULL"
      t.change :public, "tinyint(1) DEFAULT '1'"
    end
  end

  def down
    change_table :email_roles, bulk: true do |t|
      t.change :id, "int(11) unsigned NOT NULL AUTO_INCREMENT"
      t.change :user_id, "int(11) unsigned NOT NULL"
      t.change :email_id, "int(11) unsigned NOT NULL"
      t.change :public, "tinyint(1) unsigned DEFAULT '1'"
    end
  end
end
