# typed: true

class AddIndexesToIpmOrganizationMatches < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::InProductTargeting)

  def change
    change_table :ipm_organization_matches, bulk: true do |t|
      # Primary index for the main lookup pattern: organization_id, cohort, day
      # Supports queries like: IpmOrganizationMatch.where(organization_id: organization_id, cohort: cohort, day: day)
      t.index [:organization_id, :cohort, :day], name: "idx_ipm_organization_matches_org_cohort_day"

      # Index for bulk deletion pattern: day, cohort
      # Supports queries like: IpmOrganizationMatch.where(day: day, cohort: cohort)
      t.index [:day, :cohort], name: "idx_ipm_organization_matches_day_cohort"
    end
  end
end
