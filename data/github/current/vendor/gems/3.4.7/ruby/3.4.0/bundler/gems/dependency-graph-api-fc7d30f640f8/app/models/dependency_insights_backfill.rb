class DependencyInsightsBackfill < ApplicationRecord
  self.table_name = "dg_dep_insights_backfills"

  def self.backfill_outstanding
    self.where(last_backfilled_at: nil).find_each do |owner|
      owner.backfill
    end
  end

  def self.org_to_backfill(github_owner_id:, source: nil)
    backfill = self.where(github_owner_id: github_owner_id).first
    if backfill.nil?
      backfill = self.find_or_initialize_by(github_owner_id: github_owner_id)
      if backfill.persisted?
        # Return the backfill if it exists.
        backfill
      else
         # If the backfill doesn't exist, create it and return the new record.
        self.create(github_owner_id: github_owner_id, source: source)
      end
    else
      backfill
    end
  end

  def self.remove_org(github_owner_id)
    # Remove org data from backfill table and its associated package releases from materialized view
    self.where(github_owner_id: github_owner_id).destroy_all
    Views::PackageReleaseDependentCount.where(github_owner_id: github_owner_id).destroy_all
  end

  def backfill
    Views::PackageReleaseDependentCount.rebuild_for(self.github_owner_id)
    self.update(last_backfilled_at: Time.now)
  end
end
