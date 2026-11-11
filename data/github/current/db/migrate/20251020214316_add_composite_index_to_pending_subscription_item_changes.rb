# typed: strict
# frozen_string_literal: true

class AddCompositeIndexToPendingSubscriptionItemChanges < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Integrations)

  sig { void }
  def change
    change_table :pending_subscription_item_changes, bulk: true do |t|
      t.remove_index column: :free_trial
      t.index [:free_trial, :subscribable_type, :pending_plan_change_id],
              name: "index_pending_subscription_item_changes_on_free_trial_and_type"
    end
  end
end
