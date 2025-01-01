# typed: true

class ChangePagesBooleansToSigned < ActiveRecord::Migration[7.1]
  # rubocop:todo GitHub/EnsureDomainIsolationInMigration (can be dropped once table move completed)
  self.use_connection_class(ApplicationRecord::Repositories)

  def up
    return if !GitHub.enterprise? && !Rails.env.development?

    column = Page.columns_hash["four_oh_four"]
    return unless column.sql_type == "tinyint unsigned" && column.unsigned?

    change_table :pages, bulk: true do |t|
      t.change :four_oh_four, "tinyint(1) DEFAULT '0'"
    end
  end

  def down
  end
end
