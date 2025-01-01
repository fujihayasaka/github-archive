class RemoveMemexProjectActivityEvents < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Memexes)

  def change
    drop_table :memex_project_activity_events
  end
end
