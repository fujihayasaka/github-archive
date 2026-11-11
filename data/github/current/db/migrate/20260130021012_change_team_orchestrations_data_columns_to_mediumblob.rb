# typed: true
# frozen_string_literal: true

class ChangeTeamOrchestrationsDataColumnsToMediumblob < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Accounts)

  def up
    execute <<~SQL
      ALTER TABLE `team_orchestrations`
        MODIFY COLUMN `data_organization_ids` MEDIUMBLOB,
        MODIFY COLUMN `data_user_ids` MEDIUMBLOB;
    SQL
  end

  def down
    execute <<~SQL
      ALTER TABLE `team_orchestrations`
        MODIFY COLUMN `data_organization_ids` BLOB,
        MODIFY COLUMN `data_user_ids` BLOB;
    SQL
  end
end
