# typed: true
# frozen_string_literal: true

class ChangeDocusignEnvelopesBooleansToSigned < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Collab)

  def up
    change_table :docusign_envelopes, bulk: true do |t|
      t.change :id, "bigint(20) unsigned NOT NULL AUTO_INCREMENT"
      t.change :owner_id, "bigint(20) unsigned NOT NULL"
      t.change :active, "tinyint(1) DEFAULT '0'"
    end
  end

  def down
    change_table :docusign_envelopes, bulk: true do |t|
      t.change :id, "int(11) NOT NULL AUTO_INCREMENT"
      t.change :owner_id, "int(11) NOT NULL"
      t.change :active, "tinyint(1) unsigned DEFAULT '0'"
    end
  end
end
