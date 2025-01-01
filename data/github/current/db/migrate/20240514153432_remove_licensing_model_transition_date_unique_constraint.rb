class RemoveLicensingModelTransitionDateUniqueConstraint < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Billing)

  def change
    change_table :licensing_model_transitions, bulk: true do |t|
      t.remove_index name: :index_licensing_transitions_on_transition_date_and_customer_id
      t.index [:transition_date, :customer_id], name: :index_licensing_transitions_on_transition_date_and_customer_id
    end
  end
end
