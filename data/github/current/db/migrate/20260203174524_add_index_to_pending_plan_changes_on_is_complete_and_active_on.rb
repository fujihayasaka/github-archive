# typed: true
# frozen_string_literal: true

class AddIndexToPendingPlanChangesOnIsCompleteAndActiveOn < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Integrations)

  def change
    add_index :pending_plan_changes, [:is_complete, :active_on], name: "index_pending_plan_changes_on_is_complete_and_active_on"
  end
end
