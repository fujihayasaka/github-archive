# typed: true

class AddIndexesToIpmMatches < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::InProductTargeting)

  def change
    change_table :ipm_matches, bulk: true do |t|
      # Primary index for the main lookup pattern: user_id, cohort, day
      # Supports queries like: IpmMatch.where(user_id: user_id, cohort: cohort, day: day)
      t.index [:user_id, :cohort, :day], name: "idx_ipm_matches_user_cohort_day"

      # Index for bulk deletion pattern: day, cohort
      # Supports queries like: IpmMatch.where(day: day, cohort: cohort)
      t.index [:day, :cohort], name: "idx_ipm_matches_day_cohort"
    end
  end
end
