# typed: true

class AddIndexesToIpmEnterpriseMatches < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::InProductTargeting)

  def change
    change_table :ipm_enterprise_matches, bulk: true do |t|
      # Primary index for the main lookup pattern: enterprise_id, cohort, day
      # Supports queries like: IpmEnterpriseMatch.where(enterprise_id: enterprise_id, cohort: cohort, day: day)
      t.index [:enterprise_id, :cohort, :day], name: "idx_ipm_enterprise_matches_ent_cohort_day"

      # Index for bulk deletion pattern: day, cohort
      # Supports queries like: IpmEnterpriseMatch.where(day: day, cohort: cohort)
      t.index [:day, :cohort], name: "idx_ipm_enterprise_matches_day_cohort"
    end
  end
end
