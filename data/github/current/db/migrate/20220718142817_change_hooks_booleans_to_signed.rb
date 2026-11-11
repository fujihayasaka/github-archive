# typed: true
# frozen_string_literal: true

class ChangeHooksBooleansToSigned < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Mysql1)

  def up
    change_table :hooks, bulk: true do |t|
      t.change :id, "bigint(20) unsigned NOT NULL AUTO_INCREMENT"
      t.change :installation_target_id, "bigint(20) unsigned NOT NULL"
      t.change :creator_id, "bigint(20) unsigned DEFAULT NULL"
      t.change :oauth_application_id, "bigint(20) unsigned DEFAULT NULL"
      t.change :active, "tinyint(1) DEFAULT '0'"
      t.change :confirmed, "tinyint(1) DEFAULT '0'"
    end
  end

  def down
    change_table :hooks, bulk: true do |t|
      t.change :id, "int(11) NOT NULL AUTO_INCREMENT"
      t.change :installation_target_id, "int(11) NOT NULL"
      t.change :creator_id, "int(11) DEFAULT NULL"
      t.change :oauth_application_id, "int(11) DEFAULT NULL"
      t.change :active, "tinyint(1) unsigned DEFAULT '0'"
      t.change :confirmed, "tinyint(1) unsigned DEFAULT '0'"
    end
  end
end
