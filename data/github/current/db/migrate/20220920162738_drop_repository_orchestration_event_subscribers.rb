# typed: true

class DropRepositoryOrchestrationEventSubscribers < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def change
    drop_table :repository_orchestration_event_subscribers
  end
end
