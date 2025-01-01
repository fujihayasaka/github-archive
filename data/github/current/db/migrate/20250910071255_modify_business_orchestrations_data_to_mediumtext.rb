# typed: true
# frozen_string_literal: true

class ModifyBusinessOrchestrationsDataToMediumtext < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Accounts)

  def up
    connection.execute "ALTER TABLE `business_orchestrations` MODIFY `data` mediumtext;"
  end

  def down
    connection.execute "ALTER TABLE `business_orchestrations` MODIFY `data` text;"
  end
end
