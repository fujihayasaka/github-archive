# typed: true
# frozen_string_literal: true

class AddIndexesToIpmRepositoryMatches < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::InProductTargeting)

  def change
    change_table :ipm_repository_matches, bulk: true do |t|
      t.index [:repository_id, :cohort, :day], name: "idx_ipm_repository_matches_repo_cohort_day"
      t.index [:day, :cohort], name: "idx_ipm_repository_matches_day_cohort"
    end
  end
end
