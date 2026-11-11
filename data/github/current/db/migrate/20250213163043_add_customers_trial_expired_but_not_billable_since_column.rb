# typed: true
# frozen_string_literal: true

class AddCustomersTrialExpiredButNotBillableSinceColumn < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    add_column :customers, :trial_expired_but_not_billable_since, :datetime, precision: 6
  end
end
