# typed: true
class ChangeSeatCountDefaultValueForBusinessTrials < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    change_column_default :copilot_business_trials, :seat_count, from: nil, to: 0
  end
end
