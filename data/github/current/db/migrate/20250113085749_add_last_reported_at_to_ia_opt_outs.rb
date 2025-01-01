# typed: true

class AddLastReportedAtToIaOptOuts < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::UsersBallast)

  def change
    add_column :immutable_actions_opt_outs, :last_reported_at, :datetime, precision: 6, null: false
  end
end
