class UpdateLastStateChangeAtColumnToBeNotNull < ActiveRecord::Migration[7.1]
  use_connection_class ApplicationRecord::Domain::RepositoriesNotify

  def change
    change_table :repository_vulnerability_alerts, bulk: true do |t|
      t.change :last_state_change_at, :datetime, null: false
    end
  end
end
