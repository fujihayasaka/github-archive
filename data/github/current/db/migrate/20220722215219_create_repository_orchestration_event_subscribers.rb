# typed: true
class CreateRepositoryOrchestrationEventSubscribers < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def change
    create_table :repository_orchestration_event_subscribers, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.string :event_name, null: false
      t.string :subscriber_name, null: false
      t.timestamps
    end
  end
end
