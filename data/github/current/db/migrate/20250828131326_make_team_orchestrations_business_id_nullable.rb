# typed: true

class MakeTeamOrchestrationsBusinessIdNullable < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Accounts)

  def change
    change_column_null :team_orchestrations, :business_id, true
  end
end
