# typed: true
# frozen_string_literal: true

# Runs after an advisory repository is destroyed. Evaluates all associated
# advisory credits to see if they are also associated with a global advisory
# (aka Vulnerability). If not, we can destroy them, otherwise we nullify the
# repo advisory association.
class DestroyOrNullifyAdvisoryCreditsJob < ApplicationJob
  queue_as :repo_advisories

  retry_on_dirty_exit

  def perform(repository_advisory_id)
    credits = AdvisoryCredit.where(repository_advisory_id: repository_advisory_id)
    return unless credits.any?

    credits.find_each do |credit|
      ActiveRecord::Base.connected_to(role: :writing) do
        if credit.vulnerability_id.present?
          credit.update!(repository_advisory_id: nil)
        else
          credit.destroy!
        end
      end
    end
  end
end
