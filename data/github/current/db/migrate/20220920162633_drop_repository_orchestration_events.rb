# typed: true
class DropRepositoryOrchestrationEvents < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def change
    drop_table :repository_orchestration_events
  end
end
